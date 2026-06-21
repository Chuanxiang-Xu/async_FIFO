`default_nettype none

// Formal harness for the complete equal-width asynchronous FIFO core.
// Coprime write/read clock dividers exercise a continuously changing phase
// relationship under SymbiYosys multiclock semantics. Requests remain fully
// nondeterministic in each domain.
module core_formal;
    localparam DATA_WIDTH = 4;
    localparam ADDR_WIDTH = 1;
    localparam PTR_WIDTH  = ADDR_WIDTH + 1;
    localparam DEPTH      = 1 << ADDR_WIDTH;

    (* gclk *) reg global_clock;
    (* anyseq *) reg wr_en;
    (* anyseq *) reg rd_en;

    reg wr_clk = 1'b0;
    reg rd_clk = 1'b0;
    reg       wr_div = 1'b0;
    reg [1:0] rd_div = 2'b00;
    reg [4:0] init_count = 0;

    // Half-periods of two and three global steps produce unrelated edge
    // spacing over a six-step phase cycle. Keep reset asserted long enough
    // for both domains to observe multiple local edges.
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
    wire [PTR_WIDTH-1:0]  wr_used;
    wire [PTR_WIDTH-1:0]  rd_used;

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
    reg previous_read_allow;

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
            rd_history_valid <= 1'b0;
            previous_read_allow <= 1'b0;
        end
        else begin
            assert (rd_used <= DEPTH);
            assert (empty == (rd_used == 0));
            assert (almost_empty == (rd_used <= 1));

            if (rd_history_valid)
                assert (rd_valid == previous_read_allow);

            // Every accepted write stores a monotonically increasing token.
            // Therefore this assertion proves no loss, duplication, reordering,
            // underflow data, or stale-reset data can reach a valid read.
            if (rd_valid) begin
                assert (rd_data == read_sequence);
                read_sequence <= read_sequence + 1'b1;
            end

            previous_read_allow <= rd_en && !empty;
            rd_history_valid <= 1'b1;

            cover (rd_valid && (read_sequence >= DEPTH + 2));
        end
    end

endmodule

`default_nettype wire
