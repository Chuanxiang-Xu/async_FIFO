`timescale 1ns/1ps

// Smallest recommended integration: equal-width writes and reads.
module basic_fifo (
    input         wr_clk,
    input         wr_rstn,
    input         wr_en,
    input  [31:0] wr_data,
    output        full,

    input         rd_clk,
    input         rd_rstn,
    input         rd_en,
    output [31:0] rd_data,
    output        rd_valid,
    output        empty
);

    async_fifo #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(4)  // 16 words
    ) u_fifo (
        .wr_clk(wr_clk),
        .wr_rstn(wr_rstn),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .full(full),
        .almost_full(),
        .wr_used(),
        .rd_clk(rd_clk),
        .rd_rstn(rd_rstn),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .rd_valid(rd_valid),
        .empty(empty),
        .almost_empty(),
        .rd_used()
    );

endmodule
