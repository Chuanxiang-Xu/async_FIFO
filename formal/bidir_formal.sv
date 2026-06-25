`default_nettype none

// Formal harness for the full-duplex wrapper. Each direction writes an
// independent token stream, proving that the wrapper preserves ordering in
// both directions and keeps backpressure local to the affected channel.
module bidir_formal;
    localparam DATA_WIDTH = 4;
    localparam ADDR_WIDTH = 1;
    localparam DEPTH      = 1 << ADDR_WIDTH;

    (* gclk *) reg global_clock;
    (* anyseq *) reg a_tx_en;
    (* anyseq *) reg b_rx_en;
    (* anyseq *) reg b_tx_en;
    (* anyseq *) reg a_rx_en;

    reg a_clk = 1'b0;
    reg b_clk = 1'b0;
    reg       a_div = 1'b0;
    reg [1:0] b_div = 2'b00;
    reg [4:0] init_count = 0;

    always @(posedge global_clock) begin
        if (a_div) begin
            a_clk <= !a_clk;
            a_div <= 1'b0;
        end
        else begin
            a_div <= 1'b1;
        end

        if (b_div == 2) begin
            b_clk <= !b_clk;
            b_div <= 0;
        end
        else begin
            b_div <= b_div + 1'b1;
        end

        if (init_count < 12)
            init_count <= init_count + 1'b1;
    end

    wire a_rstn = (init_count >= 12);
    wire b_rstn = (init_count >= 12);

    reg [DATA_WIDTH-1:0] a_tx_sequence = 0;
    reg [DATA_WIDTH-1:0] b_rx_sequence = 0;
    reg [DATA_WIDTH-1:0] b_tx_sequence = 0;
    reg [DATA_WIDTH-1:0] a_rx_sequence = 0;

    wire                  a_tx_full;
    wire                  a_tx_almost_full;
    wire [ADDR_WIDTH:0]   a_tx_used;
    wire [DATA_WIDTH-1:0] b_rx_data;
    wire                  b_rx_valid;
    wire                  b_rx_empty;
    wire                  b_rx_almost_empty;
    wire [ADDR_WIDTH:0]   b_rx_used;

    wire                  b_tx_full;
    wire                  b_tx_almost_full;
    wire [ADDR_WIDTH:0]   b_tx_used;
    wire [DATA_WIDTH-1:0] a_rx_data;
    wire                  a_rx_valid;
    wire                  a_rx_empty;
    wire                  a_rx_almost_empty;
    wire [ADDR_WIDTH:0]   a_rx_used;

    async_bidir_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ALMOST_FULL_THRESHOLD(DEPTH - 1),
        .ALMOST_EMPTY_THRESHOLD(1)
    ) dut (
        .a_clk,
        .a_rstn,
        .b_clk,
        .b_rstn,
        .a_tx_en,
        .a_tx_data(a_tx_sequence),
        .a_tx_full,
        .a_tx_almost_full,
        .a_tx_used,
        .b_rx_en,
        .b_rx_data,
        .b_rx_valid,
        .b_rx_empty,
        .b_rx_almost_empty,
        .b_rx_used,
        .b_tx_en,
        .b_tx_data(b_tx_sequence),
        .b_tx_full,
        .b_tx_almost_full,
        .b_tx_used,
        .a_rx_en,
        .a_rx_data,
        .a_rx_valid,
        .a_rx_empty,
        .a_rx_almost_empty,
        .a_rx_used
    );

    reg previous_a2b_accept;
    reg previous_b2a_accept;
    reg b_history_valid = 1'b0;
    reg a_history_valid = 1'b0;

    always @(posedge a_clk) begin
        if (!a_rstn) begin
            a_tx_sequence <= 0;
            a_rx_sequence <= 0;
            previous_b2a_accept <= 1'b0;
            a_history_valid <= 1'b0;
        end
        else begin
            assert (a_tx_used <= DEPTH);
            assert (a_rx_used <= DEPTH);
            assert (a_tx_full == (a_tx_used == DEPTH));
            assert (a_tx_almost_full == (a_tx_used >= DEPTH - 1));
            assert (a_rx_empty == (a_rx_used == 0));
            assert (a_rx_almost_empty == (a_rx_used <= 1));

            if (a_tx_en && !a_tx_full)
                a_tx_sequence <= a_tx_sequence + 1'b1;

            if (a_history_valid)
                assert (a_rx_valid == previous_b2a_accept);

            if (a_rx_valid) begin
                assert (a_rx_data == a_rx_sequence);
                a_rx_sequence <= a_rx_sequence + 1'b1;
            end

            // B->A pressure is local. If A->B has space, A can still write
            // even when the opposite direction is full.
            if (a_history_valid &&
                $past(b_tx_full && a_tx_en && !a_tx_full))
                assert (a_tx_sequence == $past(a_tx_sequence) + 1'b1);

            previous_b2a_accept <= a_rx_en && !a_rx_empty;
            a_history_valid <= 1'b1;

            cover (a_tx_full);
            cover (a_rx_valid);
        end
    end

    always @(posedge b_clk) begin
        if (!b_rstn) begin
            b_tx_sequence <= 0;
            b_rx_sequence <= 0;
            previous_a2b_accept <= 1'b0;
            b_history_valid <= 1'b0;
        end
        else begin
            assert (b_tx_used <= DEPTH);
            assert (b_rx_used <= DEPTH);
            assert (b_tx_full == (b_tx_used == DEPTH));
            assert (b_tx_almost_full == (b_tx_used >= DEPTH - 1));
            assert (b_rx_empty == (b_rx_used == 0));
            assert (b_rx_almost_empty == (b_rx_used <= 1));

            if (b_tx_en && !b_tx_full)
                b_tx_sequence <= b_tx_sequence + 1'b1;

            if (b_history_valid)
                assert (b_rx_valid == previous_a2b_accept);

            if (b_rx_valid) begin
                assert (b_rx_data == b_rx_sequence);
                b_rx_sequence <= b_rx_sequence + 1'b1;
            end

            // A->B pressure is local. If B->A has space, B can still write
            // even when the opposite direction is full.
            if (b_history_valid &&
                $past(a_tx_full && b_tx_en && !b_tx_full))
                assert (b_tx_sequence == $past(b_tx_sequence) + 1'b1);

            previous_a2b_accept <= b_rx_en && !b_rx_empty;
            b_history_valid <= 1'b1;

            cover (b_tx_full);
            cover (b_rx_valid);
        end
    end

endmodule

`default_nettype wire
