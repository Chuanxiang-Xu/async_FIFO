`default_nettype none

// Initial-reset release checks for the supported reset contract:
// both domains start in reset, each reset deasserts on its own local clock,
// traffic remains disabled until both domains have completed initialization,
// and the two release orders are checked independently.
module reset_skew_formal #(
    parameter WRITE_FIRST = 1
);
    localparam DATA_WIDTH = 4;
    localparam ADDR_WIDTH = 1;
    localparam PTR_WIDTH  = ADDR_WIDTH + 1;
    localparam DEPTH      = 1 << ADDR_WIDTH;
    localparam WR_RELEASE = WRITE_FIRST ? 8 : 20;
    localparam RD_RELEASE = WRITE_FIRST ? 20 : 8;

    (* gclk *) reg global_clock;
    (* anyseq *) reg wr_request;
    (* anyseq *) reg rd_request;

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

    // Reset release is synchronous to the clock of the domain it controls.
    always @(posedge wr_clk) begin
        if (init_count >= WR_RELEASE)
            wr_rstn <= 1'b1;
    end

    always @(posedge rd_clk) begin
        if (init_count >= RD_RELEASE)
            rd_rstn <= 1'b1;
    end

    wire wr_en = traffic_enabled && wr_request;
    wire rd_en = traffic_enabled && rd_request;

    reg [DATA_WIDTH-1:0] write_sequence = 0;
    reg [DATA_WIDTH-1:0] read_sequence = 0;

    wire [DATA_WIDTH-1:0] rd_data;
    wire rd_valid;
    wire full;
    wire almost_full;
    wire empty;
    wire almost_empty;
    wire [PTR_WIDTH-1:0] wr_used;
    wire [PTR_WIDTH-1:0] rd_used;

    async_fifo_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ALMOST_FULL_THRESHOLD(DEPTH - 1),
        .ALMOST_EMPTY_THRESHOLD(1)
    ) dut (
        .wr_clk,
        .wr_rstn,
        .wr_en,
        .wr_data(write_sequence),
        .full,
        .almost_full,
        .wr_used,
        .rd_clk,
        .rd_rstn,
        .rd_en,
        .rd_data,
        .rd_valid,
        .empty,
        .almost_empty,
        .rd_used
    );

    reg rd_history_valid = 1'b0;
    reg previous_read_allow = 1'b0;

    always @(posedge wr_clk) begin
        if (!wr_rstn) begin
            write_sequence <= 0;
            assert (!wr_en);
            assert (!full);
            assert (wr_used == 0);
        end
        else begin
            assert (wr_used <= DEPTH);
            assert (full == (wr_used == DEPTH));

            if (!traffic_enabled)
                assert (!wr_en);

            if (wr_en && !full)
                write_sequence <= write_sequence + 1'b1;
        end
    end

    always @(posedge rd_clk) begin
        if (!rd_rstn) begin
            read_sequence <= 0;
            rd_history_valid <= 1'b0;
            previous_read_allow <= 1'b0;
            assert (!rd_en);
            assert (!rd_valid);
            assert (empty);
            assert (rd_used == 0);
        end
        else begin
            assert (rd_used <= DEPTH);
            assert (empty == (rd_used == 0));

            if (!traffic_enabled) begin
                assert (!rd_en);
                assert (!rd_valid);
            end

            if (rd_history_valid)
                assert (rd_valid == previous_read_allow);

            if (rd_valid) begin
                assert (traffic_enabled);
                assert (rd_data == read_sequence);
                read_sequence <= read_sequence + 1'b1;
            end

            previous_read_allow <= rd_en && !empty;
            rd_history_valid <= 1'b1;

            cover (rd_valid && (read_sequence >= DEPTH + 1));
        end
    end
endmodule

module reset_skew_write_first_formal;
    reset_skew_formal #(.WRITE_FIRST(1)) check();
endmodule

module reset_skew_read_first_formal;
    reset_skew_formal #(.WRITE_FIRST(0)) check();
endmodule

`default_nettype wire
