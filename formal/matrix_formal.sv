`timescale 1ns/1ps
`default_nettype none

// Concrete parameter-sweep harnesses. Widths are byte multiples with one
// side fixed at 8 bits; matrix.sby selects equal, 1:2, and 1:4 directions.
module width_matrix_formal #(
    parameter WDATA_WIDTH = 8,
    parameter RDATA_WIDTH = 8,
    parameter ADDR_WIDTH  = 3
);
    localparam RATIO = (WDATA_WIDTH > RDATA_WIDTH) ?
        WDATA_WIDTH / RDATA_WIDTH : RDATA_WIDTH / WDATA_WIDTH;
    localparam RATIO_SHIFT = (RATIO > 1) ? $clog2(RATIO) : 0;
    localparam CORE_DEPTH = 1 << (ADDR_WIDTH - RATIO_SHIFT);

    (* gclk *) reg global_clock;
    (* anyseq *) reg wr_en;
    (* anyseq *) reg rd_en;
    reg wr_clk = 0;
    reg rd_clk = 0;
    reg wr_div = 0;
    reg [1:0] rd_div = 0;
    reg [4:0] init_count = 0;
    reg [7:0] write_token = 0;
    reg [7:0] expected_token = 0;
    reg [7:0] output_count = 0;

    function [WDATA_WIDTH-1:0] write_word;
        input [7:0] base;
        integer i;
        begin
            for (i = 0; i < WDATA_WIDTH/8; i = i + 1)
                write_word[i*8 +: 8] = base + i;
        end
    endfunction

    function [RDATA_WIDTH-1:0] expected_word;
        input [7:0] base;
        integer i;
        begin
            for (i = 0; i < RDATA_WIDTH/8; i = i + 1)
                expected_word[i*8 +: 8] = base + i;
        end
    endfunction

    always @(posedge global_clock) begin
        if (wr_div) begin wr_clk <= !wr_clk; wr_div <= 0; end
        else wr_div <= 1;
        if (rd_div == 2) begin rd_clk <= !rd_clk; rd_div <= 0; end
        else rd_div <= rd_div + 1'b1;
        if (init_count < 12) init_count <= init_count + 1'b1;
    end

    wire wr_rstn = init_count >= 12;
    wire rd_rstn = init_count >= 12;
    wire [WDATA_WIDTH-1:0] wr_data = write_word(write_token);
    wire [RDATA_WIDTH-1:0] rd_data;
    wire rd_valid, empty, full, almost_empty, almost_full;
    wire [ADDR_WIDTH:0] wr_core_used, rd_core_used;

    async_fifo_width_conv #(
        .WDATA_WIDTH(WDATA_WIDTH), .RDATA_WIDTH(RDATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk, .wr_rstn, .wr_en, .wr_data,
        .rd_clk, .rd_rstn, .rd_en, .rd_data, .rd_valid,
        .empty, .full, .almost_empty, .almost_full,
        .wr_core_used, .rd_core_used
    );

    always @(posedge wr_clk) begin
        if (!wr_rstn) write_token <= 0;
        else begin
            if (wr_en && !full)
                write_token <= write_token + WDATA_WIDTH/8;
            assert (wr_core_used <= CORE_DEPTH);
        end
    end

    always @(posedge rd_clk) begin
        if (!rd_rstn) begin
            expected_token <= 0;
            output_count <= 0;
        end
        else begin
            assert (rd_core_used <= CORE_DEPTH);
            if (rd_valid) begin
                assert (rd_data == expected_word(expected_token));
                expected_token <= expected_token + RDATA_WIDTH/8;
                output_count <= output_count + 1'b1;
            end
            cover (output_count >= 2);
        end
    end
endmodule


module stream_matrix_formal #(
    parameter WDATA_WIDTH = 8,
    parameter RDATA_WIDTH = 8,
    parameter ADDR_WIDTH  = 3
);
    localparam WBYTES = WDATA_WIDTH / 8;
    localparam RBYTES = RDATA_WIDTH / 8;
    localparam RATIO = (WDATA_WIDTH > RDATA_WIDTH) ?
        WDATA_WIDTH / RDATA_WIDTH : RDATA_WIDTH / WDATA_WIDTH;
    localparam RATIO_SHIFT = (RATIO > 1) ? $clog2(RATIO) : 0;
    localparam CORE_DEPTH = 1 << (ADDR_WIDTH - RATIO_SHIFT);
    localparam WRITE_SLICES = (RDATA_WIDTH > WDATA_WIDTH) ? RATIO : 1;
    localparam READ_SLICES = (WDATA_WIDTH > RDATA_WIDTH) ? RATIO : 1;

    (* gclk *) reg global_clock;
    (* anyseq *) reg offer_valid;
    (* anyseq *) reg rd_ready;
    reg wr_clk = 0;
    reg rd_clk = 0;
    reg wr_div = 0;
    reg [1:0] rd_div = 0;
    reg [4:0] init_count = 0;
    reg wr_valid = 0;
    reg [7:0] write_token = 0;
    reg [7:0] expected_token = 0;
    reg [2:0] write_slice = 0;
    reg [2:0] expected_slice = 0;
    reg [7:0] output_count = 0;
    reg stalled = 0;
    reg [RDATA_WIDTH-1:0] stalled_data = 0;
    reg [RBYTES-1:0] stalled_keep = 0;
    reg stalled_last = 0;

    function [WDATA_WIDTH-1:0] write_word;
        input [7:0] base;
        integer i;
        begin
            for (i = 0; i < WBYTES; i = i + 1)
                write_word[i*8 +: 8] = base + i;
        end
    endfunction

    function [RDATA_WIDTH-1:0] expected_word;
        input [7:0] base;
        integer i;
        begin
            for (i = 0; i < RBYTES; i = i + 1)
                expected_word[i*8 +: 8] = base + i;
        end
    endfunction

    always @(posedge global_clock) begin
        if (wr_div) begin wr_clk <= !wr_clk; wr_div <= 0; end
        else wr_div <= 1;
        if (rd_div == 2) begin rd_clk <= !rd_clk; rd_div <= 0; end
        else rd_div <= rd_div + 1'b1;
        if (init_count < 12) init_count <= init_count + 1'b1;
    end

    wire wr_rstn = init_count >= 12;
    wire rd_rstn = init_count >= 12;
    wire [WDATA_WIDTH-1:0] wr_data = write_word(write_token);
    wire [WBYTES-1:0] wr_keep = {WBYTES{1'b1}};
    wire wr_last = write_slice == WRITE_SLICES - 1;
    wire wr_ready;
    wire rd_valid;
    wire [RDATA_WIDTH-1:0] rd_data;
    wire [RBYTES-1:0] rd_keep;
    wire rd_last;
    wire full, empty, almost_full, almost_empty;
    wire [ADDR_WIDTH:0] wr_core_used, rd_core_used;
    wire expected_last = expected_slice == READ_SLICES - 1;

    async_fifo_stream #(
        .WDATA_WIDTH(WDATA_WIDTH), .RDATA_WIDTH(RDATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk, .wr_rstn, .wr_valid, .wr_ready, .wr_data, .wr_keep,
        .wr_last, .full, .almost_full, .wr_core_used,
        .rd_clk, .rd_rstn, .rd_valid, .rd_ready, .rd_data, .rd_keep,
        .rd_last, .empty, .almost_empty, .rd_core_used
    );

    always @(posedge wr_clk) begin
        if (!wr_rstn) begin
            wr_valid <= 0;
            write_token <= 0;
            write_slice <= 0;
        end
        else begin
            if (wr_valid && wr_ready) begin
                write_token <= write_token + WBYTES;
                write_slice <= wr_last ? 0 : write_slice + 1'b1;
            end
            if (!wr_valid || wr_ready) wr_valid <= offer_valid;
            assert (full == !wr_ready);
            assert (wr_core_used <= CORE_DEPTH);
        end
    end

    always @(posedge rd_clk) begin
        if (!rd_rstn) begin
            expected_token <= 0;
            expected_slice <= 0;
            output_count <= 0;
            stalled <= 0;
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
                assert (rd_data == expected_word(expected_token));
                assert (rd_keep == {RBYTES{1'b1}});
                assert (rd_last == expected_last);
            end
            if (rd_valid && rd_ready) begin
                expected_token <= expected_token + RBYTES;
                expected_slice <= expected_last ? 0 : expected_slice + 1'b1;
                output_count <= output_count + 1'b1;
            end
            stalled <= rd_valid && !rd_ready;
            if (rd_valid && !rd_ready) begin
                stalled_data <= rd_data;
                stalled_keep <= rd_keep;
                stalled_last <= rd_last;
            end
            cover (output_count >= 2);
        end
    end
endmodule

`default_nettype wire
