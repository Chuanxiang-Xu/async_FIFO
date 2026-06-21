`timescale 1ns/1ps
`default_nettype none

// Coordinated-startup reset checks for the packet stream wrapper. Both reset
// release orders are exercised; each reset deasserts on its local clock and
// traffic remains disabled until both domains have initialized.
module stream_reset_skew_formal #(
    parameter WRITE_FIRST = 1
);
    localparam ADDR_WIDTH = 3;
    localparam CORE_DEPTH = 1 << (ADDR_WIDTH - 1);
    localparam WR_RELEASE = WRITE_FIRST ? 8 : 20;
    localparam RD_RELEASE = WRITE_FIRST ? 20 : 8;

    (* gclk *) reg global_clock;
    (* anyseq *) reg offer_valid;
    (* anyseq *) reg sink_ready;

    reg wr_clk = 1'b0;
    reg rd_clk = 1'b0;
    reg wr_div = 1'b0;
    reg [1:0] rd_div = 2'b00;
    reg [5:0] init_count = 0;
    reg wr_rstn = 1'b0;
    reg rd_rstn = 1'b0;
    reg traffic_enabled = 1'b0;

    always @(posedge global_clock) begin
        if (wr_div) begin
            wr_clk <= !wr_clk;
            wr_div <= 1'b0;
        end
        else begin
            wr_div <= 1'b1;
        end

        if (rd_div == 2) begin
            rd_clk <= !rd_clk;
            rd_div <= 0;
        end
        else begin
            rd_div <= rd_div + 1'b1;
        end

        if (init_count < 32)
            init_count <= init_count + 1'b1;

        if (wr_rstn && rd_rstn)
            traffic_enabled <= 1'b1;
    end

    always @(posedge wr_clk) begin
        if (init_count >= WR_RELEASE)
            wr_rstn <= 1'b1;
    end

    always @(posedge rd_clk) begin
        if (init_count >= RD_RELEASE)
            rd_rstn <= 1'b1;
    end

    // Use the narrow-to-wide packet path so the proof crosses the write pack
    // and pending state, asynchronous core, and both read-side payload slots.
    reg wr_valid = 1'b0;
    reg [7:0] wr_data = 0;
    reg [1:0] write_phase = 0;
    wire [0:0] wr_keep = 1'b1;
    wire wr_last = write_phase[1];
    wire wr_ready;

    wire rd_valid;
    wire rd_ready = traffic_enabled && sink_ready;
    wire [15:0] rd_data;
    wire [1:0] rd_keep;
    wire rd_last;
    wire full;
    wire empty;
    wire almost_full;
    wire almost_empty;
    wire [ADDR_WIDTH:0] wr_core_used;
    wire [ADDR_WIDTH:0] rd_core_used;

    reg [7:0] expected_token = 0;
    reg [1:0] expected_phase = 0;
    reg stalled = 1'b0;
    reg [15:0] stalled_data = 0;
    reg [1:0] stalled_keep = 0;
    reg stalled_last = 1'b0;

    wire expected_partial = expected_phase[1];
    wire [15:0] expected_data = expected_partial ?
        {8'b0, expected_token} :
        {expected_token + 1'b1, expected_token};
    wire [1:0] expected_keep = expected_partial ? 2'b01 : 2'b11;
    wire expected_last = expected_partial;

    async_fifo_stream #(
        .WDATA_WIDTH(8),
        .RDATA_WIDTH(16),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk,
        .wr_rstn,
        .wr_valid,
        .wr_ready,
        .wr_data,
        .wr_keep,
        .wr_last,
        .full,
        .almost_full,
        .wr_core_used,
        .rd_clk,
        .rd_rstn,
        .rd_valid,
        .rd_ready,
        .rd_data,
        .rd_keep,
        .rd_last,
        .empty,
        .almost_empty,
        .rd_core_used
    );

    always @(posedge wr_clk) begin
        if (!wr_rstn) begin
            wr_valid <= 1'b0;
            wr_data <= 0;
            write_phase <= 0;
            assert (wr_core_used == 0);
        end
        else begin
            assert (full == !wr_ready);
            assert (wr_core_used <= CORE_DEPTH);

            if (!traffic_enabled) begin
                wr_valid <= 1'b0;
                assert (!wr_valid);
                assert (wr_core_used == 0);
            end
            else begin
                if (wr_valid && wr_ready) begin
                    wr_data <= wr_data + 1'b1;
                    write_phase <= write_phase + 1'b1;
                end

                if (!wr_valid || wr_ready)
                    wr_valid <= offer_valid;
            end
        end
    end

    always @(posedge rd_clk) begin
        if (!rd_rstn) begin
            expected_token <= 0;
            expected_phase <= 0;
            stalled <= 1'b0;
            stalled_data <= 0;
            stalled_keep <= 0;
            stalled_last <= 1'b0;
            assert (!rd_valid);
            assert (rd_core_used == 0);
        end
        else begin
            assert (rd_core_used <= CORE_DEPTH);
            assert (!rd_last || rd_valid);

            if (!traffic_enabled) begin
                assert (!rd_ready);
                assert (!rd_valid);
                assert (rd_core_used == 0);
            end

            if (stalled) begin
                assert (rd_valid);
                assert ({rd_data, rd_keep, rd_last} ==
                        {stalled_data, stalled_keep, stalled_last});
            end

            if (rd_valid) begin
                assert (traffic_enabled);
                assert ({rd_data, rd_keep, rd_last} ==
                        {expected_data, expected_keep, expected_last});
            end

            if (rd_valid && rd_ready) begin
                expected_token <= expected_partial ?
                    expected_token + 1'b1 :
                    expected_token + 2'd2;
                expected_phase <= expected_partial ?
                    expected_phase + 1'b1 :
                    expected_phase + 2'd2;
            end

            stalled <= rd_valid && !rd_ready;
            if (rd_valid && !rd_ready) begin
                stalled_data <= rd_data;
                stalled_keep <= rd_keep;
                stalled_last <= rd_last;
            end

            cover (rd_valid && rd_ready && rd_last);
            cover (rd_valid && rd_ready && !rd_last);
        end
    end
endmodule

module stream_reset_skew_write_first_formal;
    stream_reset_skew_formal #(.WRITE_FIRST(1)) check();
endmodule

module stream_reset_skew_read_first_formal;
    stream_reset_skew_formal #(.WRITE_FIRST(0)) check();
endmodule

`default_nettype wire
