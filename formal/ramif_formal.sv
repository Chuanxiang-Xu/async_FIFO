`default_nettype none

// Formal harness for async_fifo_ramif with a one-cycle synchronous read RAM
// model. The RAM model matches the public RAMIF contract and lets the harness
// prove ordering plus rd_valid alignment through the external storage boundary.
module ramif_formal;
    localparam DATA_WIDTH = 4;
    localparam ADDR_WIDTH = 1;
    localparam DEPTH      = 1 << ADDR_WIDTH;

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

    wire                  full;
    wire                  almost_full;
    wire [ADDR_WIDTH:0]   wr_used;
    wire [DATA_WIDTH-1:0] rd_data;
    wire                  rd_valid;
    wire                  empty;
    wire                  almost_empty;
    wire [ADDR_WIDTH:0]   rd_used;

    wire                  ram_wr_clk;
    wire                  ram_wr_en;
    wire [ADDR_WIDTH-1:0] ram_wr_addr;
    wire [DATA_WIDTH-1:0] ram_wr_data;
    wire                  ram_rd_clk;
    wire                  ram_rd_en;
    wire [ADDR_WIDTH-1:0] ram_rd_addr;
    reg  [DATA_WIDTH-1:0] ram_rd_data;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    async_fifo_ramif #(
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
        .rd_used,
        .ram_wr_clk,
        .ram_wr_en,
        .ram_wr_addr,
        .ram_wr_data,
        .ram_rd_clk,
        .ram_rd_en,
        .ram_rd_addr,
        .ram_rd_data
    );

    always @(posedge ram_wr_clk) begin
        if (ram_wr_en)
            mem[ram_wr_addr] <= ram_wr_data;
    end

    always @(posedge ram_rd_clk) begin
        if (ram_rd_en)
            ram_rd_data <= mem[ram_rd_addr];
    end

    reg previous_read_allow;
    reg rd_history_valid = 1'b0;

    always @(posedge wr_clk) begin
        if (!wr_rstn) begin
            write_sequence <= 0;
        end
        else begin
            assert (ram_wr_clk == wr_clk);
            assert (wr_used <= DEPTH);
            assert (full == (wr_used == DEPTH));
            assert (almost_full == (wr_used >= DEPTH - 1));
            assert (ram_wr_en == (wr_en && !full));

            if (ram_wr_en) begin
                assert (ram_wr_data == write_sequence);
                write_sequence <= write_sequence + 1'b1;
            end

            cover (full);
        end
    end

    always @(posedge rd_clk) begin
        if (!rd_rstn) begin
            read_sequence <= 0;
            previous_read_allow <= 1'b0;
            rd_history_valid <= 1'b0;
        end
        else begin
            assert (ram_rd_clk == rd_clk);
            assert (rd_used <= DEPTH);
            assert (empty == (rd_used == 0));
            assert (almost_empty == (rd_used <= 1));
            assert (ram_rd_en == (rd_en && !empty));
            assert (rd_data == ram_rd_data);

            if (rd_history_valid)
                assert (rd_valid == previous_read_allow);

            if (rd_valid) begin
                assert (rd_data == read_sequence);
                read_sequence <= read_sequence + 1'b1;
            end

            previous_read_allow <= rd_en && !empty;
            rd_history_valid <= 1'b1;

            cover (rd_valid);
        end
    end

endmodule

`default_nettype wire
