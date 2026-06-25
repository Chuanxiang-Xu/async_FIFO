`timescale 1ns/1ps

// Full-duplex CDC wrapper built from two independent async_fifo instances.
//
// a_tx_* moves data from domain A to domain B and appears as b_rx_*.
// b_tx_* moves data from domain B to domain A and appears as a_rx_*.
// The two directions share no storage, flags, or transaction state.
module async_bidir_fifo #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 9,
    parameter ALMOST_FULL_THRESHOLD = (1 << ADDR_WIDTH) - 1,
    parameter ALMOST_EMPTY_THRESHOLD = 1
) (
    input                   a_clk,
    input                   a_rstn,
    input                   b_clk,
    input                   b_rstn,

    input                   a_tx_en,
    input  [DATA_WIDTH-1:0] a_tx_data,
    output                  a_tx_full,
    output                  a_tx_almost_full,
    output [ADDR_WIDTH:0]   a_tx_used,

    input                   b_rx_en,
    output [DATA_WIDTH-1:0] b_rx_data,
    output                  b_rx_valid,
    output                  b_rx_empty,
    output                  b_rx_almost_empty,
    output [ADDR_WIDTH:0]   b_rx_used,

    input                   b_tx_en,
    input  [DATA_WIDTH-1:0] b_tx_data,
    output                  b_tx_full,
    output                  b_tx_almost_full,
    output [ADDR_WIDTH:0]   b_tx_used,

    input                   a_rx_en,
    output [DATA_WIDTH-1:0] a_rx_data,
    output                  a_rx_valid,
    output                  a_rx_empty,
    output                  a_rx_almost_empty,
    output [ADDR_WIDTH:0]   a_rx_used
);

    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ALMOST_FULL_THRESHOLD(ALMOST_FULL_THRESHOLD),
        .ALMOST_EMPTY_THRESHOLD(ALMOST_EMPTY_THRESHOLD)
    ) u_a2b_fifo (
        .wr_clk       (a_clk),
        .wr_rstn      (a_rstn),
        .wr_en        (a_tx_en),
        .wr_data      (a_tx_data),
        .full         (a_tx_full),
        .almost_full  (a_tx_almost_full),
        .wr_used      (a_tx_used),
        .rd_clk       (b_clk),
        .rd_rstn      (b_rstn),
        .rd_en        (b_rx_en),
        .rd_data      (b_rx_data),
        .rd_valid     (b_rx_valid),
        .empty        (b_rx_empty),
        .almost_empty (b_rx_almost_empty),
        .rd_used      (b_rx_used)
    );

    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ALMOST_FULL_THRESHOLD(ALMOST_FULL_THRESHOLD),
        .ALMOST_EMPTY_THRESHOLD(ALMOST_EMPTY_THRESHOLD)
    ) u_b2a_fifo (
        .wr_clk       (b_clk),
        .wr_rstn      (b_rstn),
        .wr_en        (b_tx_en),
        .wr_data      (b_tx_data),
        .full         (b_tx_full),
        .almost_full  (b_tx_almost_full),
        .wr_used      (b_tx_used),
        .rd_clk       (a_clk),
        .rd_rstn      (a_rstn),
        .rd_en        (a_rx_en),
        .rd_data      (a_rx_data),
        .rd_valid     (a_rx_valid),
        .empty        (a_rx_empty),
        .almost_empty (a_rx_almost_empty),
        .rd_used      (a_rx_used)
    );

    initial begin
        if (DATA_WIDTH < 1)
            $fatal(1, "DATA_WIDTH must be at least one");
        if (ADDR_WIDTH < 1)
            $fatal(1, "ADDR_WIDTH must be at least one");
    end

endmodule
