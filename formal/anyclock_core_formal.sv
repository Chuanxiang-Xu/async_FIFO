`default_nettype none

// Equal-width core proof with independently varying symbolic clock rates.
// Each domain advances by an independently symbolic nonzero phase increment.
// The increments are constant within one trace but range over all permitted
// values across the proof, covering a family of frequency ratios, arbitrary
// initial read-clock phase, and coincident edges.
module anyclock_core_formal #(
    parameter DATA_WIDTH = 4,
    parameter ADDR_WIDTH = 1
);
    localparam PTR_WIDTH = ADDR_WIDTH + 1;
    localparam DEPTH = 1 << ADDR_WIDTH;

    (* gclk *) reg global_clock;
    (* anyconst *) reg [3:0] wr_step;
    (* anyconst *) reg [3:0] rd_step;
    (* anyseq *) reg wr_en;
    (* anyseq *) reg rd_en;

    reg [3:0] wr_phase = 0;
    reg [3:0] rd_phase;
    reg [5:0] init_count = 0;

    wire wr_clk = wr_phase[3];
    wire rd_clk = rd_phase[3];
    wire wr_rstn = init_count >= 12;
    wire rd_rstn = init_count >= 12;

    always @(posedge global_clock) begin
        // A step below half the accumulator range prevents multiple hidden
        // clock edges per formal step. Nonzero steps guarantee progress.
        assume (wr_step >= 2 && wr_step <= 7);
        assume (rd_step >= 2 && rd_step <= 7);
        wr_phase <= wr_phase + wr_step;
        rd_phase <= rd_phase + rd_step;
        if (init_count < 32)
            init_count <= init_count + 1'b1;
    end

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
        .wr_clk, .wr_rstn, .wr_en, .wr_data(write_sequence),
        .full, .almost_full, .wr_used,
        .rd_clk, .rd_rstn, .rd_en, .rd_data, .rd_valid,
        .empty, .almost_empty, .rd_used
    );

    reg rd_history_valid = 0;
    reg previous_read_allow = 0;

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
            rd_history_valid <= 0;
            previous_read_allow <= 0;
        end
        else begin
            assert (rd_used <= DEPTH);
            assert (empty == (rd_used == 0));
            assert (almost_empty == (rd_used <= 1));
            if (rd_history_valid)
                assert (rd_valid == previous_read_allow);
            if (rd_valid) begin
                assert (rd_data == read_sequence);
                read_sequence <= read_sequence + 1'b1;
            end
            previous_read_allow <= rd_en && !empty;
            rd_history_valid <= 1'b1;
            cover (rd_valid && (read_sequence >= DEPTH + 1));
        end
    end
endmodule

`default_nettype wire
