`timescale 1ns/1ps

// Minimal public entry point for the equal-width asynchronous FIFO.
// Optional protocol features live in rtl/wrappers/.
//
// DATA_WIDTH:
//   Number of bits in each stored word.
//
// ADDR_WIDTH:
//   Number of RAM address bits. The FIFO stores 2**ADDR_WIDTH words.
//   The internal read/write pointers are automatically one bit wider to
//   distinguish empty from full after address wraparound.
module async_fifo #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 9,
    parameter ALMOST_FULL_THRESHOLD = (1 << ADDR_WIDTH) - 1,
    parameter ALMOST_EMPTY_THRESHOLD = 1
) (
    input                   wr_clk,
    input                   wr_rstn,
    input                   wr_en,
    input  [DATA_WIDTH-1:0] wr_data,
    output                  full,
    output                  almost_full,
    output [ADDR_WIDTH:0]   wr_used,

    input                   rd_clk,
    input                   rd_rstn,
    input                   rd_en,
    output [DATA_WIDTH-1:0] rd_data,
    output                  rd_valid,
    output                  empty,
    output                  almost_empty,
    output [ADDR_WIDTH:0]   rd_used
);

    async_fifo_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ALMOST_FULL_THRESHOLD(ALMOST_FULL_THRESHOLD),
        .ALMOST_EMPTY_THRESHOLD(ALMOST_EMPTY_THRESHOLD)
    ) u_async_fifo_core (
        .wr_clk   (wr_clk),
        .wr_rstn  (wr_rstn),
        .wr_en    (wr_en),
        .wr_data  (wr_data),
        .full     (full),
        .almost_full(almost_full),
        .wr_used  (wr_used),
        .rd_clk   (rd_clk),
        .rd_rstn  (rd_rstn),
        .rd_en    (rd_en),
        .rd_data  (rd_data),
        .rd_valid (rd_valid),
        .empty    (empty),
        .almost_empty(almost_empty),
        .rd_used  (rd_used)
    );

    initial begin
        if (DATA_WIDTH < 1)
            $fatal(1, "DATA_WIDTH must be at least one");
        if (ADDR_WIDTH < 1)
            $fatal(1, "ADDR_WIDTH must be at least one");
    end

endmodule
