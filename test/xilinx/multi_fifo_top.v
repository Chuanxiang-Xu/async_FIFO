`timescale 1ns/1ps

module multi_fifo_top (
    input small_wr_clk,
    input small_rd_clk,
    input large_wr_clk,
    input large_rd_clk,
    input rstn,
    input wr_en,
    input rd_en,
    input [7:0] data_in,
    output [7:0] data_out,
    output [3:0] status
);
    wire [7:0] small_data;
    wire [7:0] large_data;
    wire small_full;
    wire small_empty;
    wire large_full;
    wire large_empty;

    async_fifo #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(3)
    ) u_fifo_small (
        .wr_clk(small_wr_clk), .wr_rstn(rstn),
        .wr_en(wr_en), .wr_data(data_in),
        .full(small_full), .almost_full(), .wr_used(),
        .rd_clk(small_rd_clk), .rd_rstn(rstn),
        .rd_en(rd_en), .rd_data(small_data), .rd_valid(),
        .empty(small_empty), .almost_empty(), .rd_used()
    );

    async_fifo #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(5)
    ) u_fifo_large (
        .wr_clk(large_wr_clk), .wr_rstn(rstn),
        .wr_en(wr_en), .wr_data(data_in),
        .full(large_full), .almost_full(), .wr_used(),
        .rd_clk(large_rd_clk), .rd_rstn(rstn),
        .rd_en(rd_en), .rd_data(large_data), .rd_valid(),
        .empty(large_empty), .almost_empty(), .rd_used()
    );

    assign data_out = small_data ^ large_data;
    assign status = {large_full, large_empty, small_full, small_empty};
endmodule
