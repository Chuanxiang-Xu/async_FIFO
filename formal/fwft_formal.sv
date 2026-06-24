`default_nettype none

// Formal harness for the equal-width first-word-fall-through wrapper.
// Deterministic write tokens plus read-side pop checks prove that visible FWFT
// data is neither lost, duplicated, nor reordered.
module fwft_formal;
    localparam DATA_WIDTH = 4;
    localparam ADDR_WIDTH = 2;
    localparam DEPTH      = 1 << ADDR_WIDTH;
    localparam MAX_RD_USED = DEPTH + 3;

    (* gclk *) reg global_clock;
    (* anyseq *) reg wr_en;
    (* anyseq *) reg rd_en;

    reg wr_clk = 1'b0;
    reg rd_clk = 1'b0;
    reg       wr_div = 1'b0;
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

    reg [DATA_WIDTH-1:0] write_sequence = 0;
    reg [DATA_WIDTH-1:0] read_sequence  = 0;

    wire [DATA_WIDTH-1:0] rd_data;
    wire                  rd_valid;
    wire                  full;
    wire                  almost_full;
    wire                  empty;
    wire                  almost_empty;
    wire [ADDR_WIDTH:0]   wr_used;
    wire [ADDR_WIDTH:0]   rd_used;

    async_fifo_fwft #(
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

    reg stalled = 1'b0;
    reg [DATA_WIDTH-1:0] stalled_data = 0;

    always @(posedge wr_clk) begin
        if (!wr_rstn) begin
            write_sequence <= 0;
        end
        else begin
            assert (wr_used <= DEPTH);
            assert (full == (wr_used == DEPTH));
            assert (almost_full == (wr_used >= DEPTH - 1));

            if (wr_en && !full)
                write_sequence <= write_sequence + 1'b1;

            cover (full);
        end
    end

    always @(posedge rd_clk) begin
        if (!rd_rstn) begin
            read_sequence <= 0;
            stalled <= 1'b0;
            stalled_data <= 0;
            assert (!rd_valid);
            assert (empty);
        end
        else begin
            assert (empty == !rd_valid);
            assert (rd_used <= MAX_RD_USED[ADDR_WIDTH:0]);
            assert (almost_empty == (rd_used <= 1));

            if (stalled) begin
                assert (rd_valid);
                assert (rd_data == stalled_data);
            end

            // A FWFT pop consumes the currently visible word. Since writes
            // store an increasing sequence, this single assertion protects
            // ordering, no duplicate pops, and no dropped visible words.
            if (rd_valid && rd_en) begin
                assert (rd_data == read_sequence);
                read_sequence <= read_sequence + 1'b1;
            end

            stalled <= rd_valid && !rd_en;
            if (rd_valid && !rd_en)
                stalled_data <= rd_data;

            cover (rd_valid);
            cover (rd_valid && !rd_en);
            cover (rd_valid && rd_en && (read_sequence >= DEPTH + 2));
        end
    end

endmodule

`default_nettype wire
