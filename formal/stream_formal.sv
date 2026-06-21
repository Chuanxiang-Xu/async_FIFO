`timescale 1ns/1ps
`default_nettype none

// Packet-aware wrapper checks using unique deterministic data tokens and
// independent read-side expectation state. Source valid and sink ready remain
// nondeterministic, so stalls and changing asynchronous clock phase are still
// explored without a cross-clock shadow RAM.

module stream_pack_formal;
    localparam ADDR_WIDTH = 3;
    localparam CORE_DEPTH = 1 << (ADDR_WIDTH - 1);

    (* gclk *) reg global_clock;
    (* anyseq *) reg offer_valid;
    (* anyseq *) reg rd_ready;

    reg wr_clk = 1'b0;
    reg rd_clk = 1'b0;
    reg wr_div = 1'b0;
    reg [1:0] rd_div = 2'b00;
    reg [4:0] init_count = 0;

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

        if (init_count < 12)
            init_count <= init_count + 1'b1;
    end

    wire wr_rstn = (init_count >= 12);
    wire rd_rstn = (init_count >= 12);

    reg wr_valid = 1'b0;
    reg [7:0] wr_data = 0;
    reg [1:0] write_phase = 0;
    wire [0:0] wr_keep = 1'b1;
    // Phase 0/1 forms one full non-final word. Phases 2 and 3 are
    // independently flushed one-byte final words.
    wire wr_last = write_phase[1];
    wire wr_ready;

    wire rd_valid;
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

    // Protocol-compliant source. The token and its derived metadata remain
    // stable while valid is waiting for ready.
    always @(posedge wr_clk) begin
        if (!wr_rstn) begin
            wr_valid <= 1'b0;
            wr_data <= 0;
            write_phase <= 0;
        end
        else begin
            if (wr_valid && wr_ready) begin
                wr_data <= wr_data + 1'b1;
                write_phase <= write_phase + 1'b1;
            end

            if (!wr_valid || wr_ready)
                wr_valid <= offer_valid;

            assert (full == !wr_ready);
            assert (wr_core_used <= CORE_DEPTH);
            cover (full);
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
        end
        else begin
            assert (rd_core_used <= CORE_DEPTH);
            assert (!rd_last || rd_valid);

            if (stalled) begin
                assert (rd_valid);
                assert ({rd_data, rd_keep, rd_last} ==
                        {stalled_data, stalled_keep, stalled_last});
            end

            if (rd_valid) begin
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


module stream_split_formal;
    localparam ADDR_WIDTH = 3;
    localparam CORE_DEPTH = 1 << (ADDR_WIDTH - 1);

    (* gclk *) reg global_clock;
    (* anyseq *) reg offer_valid;
    (* anyseq *) reg rd_ready;

    reg wr_clk = 1'b0;
    reg rd_clk = 1'b0;
    reg wr_div = 1'b0;
    reg [1:0] rd_div = 2'b00;
    reg [4:0] init_count = 0;

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

        if (init_count < 12)
            init_count <= init_count + 1'b1;
    end

    wire wr_rstn = (init_count >= 12);
    wire rd_rstn = (init_count >= 12);

    reg wr_valid = 1'b0;
    reg [15:0] write_token = 0;
    wire [31:0] wr_data = {write_token + 1'b1, write_token};
    // Four-word repeating packet pattern:
    //   base 0: full, non-final
    //   base 2: partial, final
    //   base 4: full, non-final
    //   base 6: full, final
    wire [2:0] write_phase = write_token[2:0];
    wire wr_last = (write_phase == 3'd2) || (write_phase == 3'd6);
    wire [3:0] wr_keep =
        (write_phase == 3'd2) ? 4'b0011 : 4'b1111;
    wire wr_ready;

    wire rd_valid;
    wire [15:0] rd_data;
    wire [1:0] rd_keep;
    wire rd_last;
    wire full;
    wire empty;
    wire almost_full;
    wire almost_empty;
    wire [ADDR_WIDTH:0] wr_core_used;
    wire [ADDR_WIDTH:0] rd_core_used;

    reg [15:0] expected_base = 0;
    reg expected_high = 1'b0;
    reg stalled = 1'b0;
    reg [15:0] stalled_data = 0;
    reg [1:0] stalled_keep = 0;
    reg stalled_last = 1'b0;

    wire [2:0] expected_phase = expected_base[2:0];
    wire expected_partial = (expected_phase == 3'd2);
    wire expected_word_last =
        (expected_phase == 3'd2) || (expected_phase == 3'd6);
    wire [15:0] expected_data =
        expected_high ? expected_base + 1'b1 : expected_base;
    wire [1:0] expected_keep = 2'b11;
    wire expected_last =
        expected_word_last && (expected_partial || expected_high);

    async_fifo_stream #(
        .WDATA_WIDTH(32),
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
            write_token <= 0;
        end
        else begin
            if (wr_valid && wr_ready)
                write_token <= write_token + 2'd2;

            if (!wr_valid || wr_ready)
                wr_valid <= offer_valid;

            assert (full == !wr_ready);
            assert (wr_core_used <= CORE_DEPTH);
            cover (full);
        end
    end

    always @(posedge rd_clk) begin
        if (!rd_rstn) begin
            expected_base <= 0;
            expected_high <= 1'b0;
            stalled <= 1'b0;
            stalled_data <= 0;
            stalled_keep <= 0;
            stalled_last <= 1'b0;
        end
        else begin
            assert (rd_core_used <= CORE_DEPTH);
            assert (!rd_last || rd_valid);

            if (stalled) begin
                assert (rd_valid);
                assert ({rd_data, rd_keep, rd_last} ==
                        {stalled_data, stalled_keep, stalled_last});
            end

            if (rd_valid) begin
                assert ({rd_data, rd_keep, rd_last} ==
                        {expected_data, expected_keep, expected_last});
            end

            if (rd_valid && rd_ready) begin
                if (expected_partial || expected_high) begin
                    expected_base <= expected_base + 2'd2;
                    expected_high <= 1'b0;
                end
                else begin
                    expected_high <= 1'b1;
                end
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

`default_nettype wire
