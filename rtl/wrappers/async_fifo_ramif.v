`timescale 1ns/1ps

// Equal-width asynchronous FIFO control with an external simple dual-port RAM.
//
// This experimental wrapper keeps the Cummings-style pointer, synchronizer,
// full/empty, and rd_valid behavior in this repository, but exposes the
// storage transaction so an integration can provide its own RAM implementation.
// The RAM contract matches rtl/core/fifo_mem.v: synchronous write, synchronous
// read, fixed one-read-clock latency, and no RAM backpressure.
module async_fifo_ramif #(
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
    output reg              rd_valid,
    output                  empty,
    output                  almost_empty,
    output [ADDR_WIDTH:0]   rd_used,

    output                  ram_wr_clk,
    output                  ram_wr_en,
    output [ADDR_WIDTH-1:0] ram_wr_addr,
    output [DATA_WIDTH-1:0] ram_wr_data,

    output                  ram_rd_clk,
    output                  ram_rd_en,
    output [ADDR_WIDTH-1:0] ram_rd_addr,
    input  [DATA_WIDTH-1:0] ram_rd_data
);

    wire [ADDR_WIDTH-1:0] waddr;
    wire [ADDR_WIDTH-1:0] raddr;

    wire [ADDR_WIDTH:0] wptr_gray;
    wire [ADDR_WIDTH:0] rptr_gray;
    wire [ADDR_WIDTH:0] wptr_gray_sync;
    wire [ADDR_WIDTH:0] rptr_gray_sync;

    wire write_allow = wr_rstn && wr_en && !full;
    wire read_allow  = rd_rstn && rd_en && !empty;

    assign ram_wr_clk  = wr_clk;
    assign ram_wr_en   = write_allow;
    assign ram_wr_addr = waddr;
    assign ram_wr_data = wr_data;

    assign ram_rd_clk  = rd_clk;
    assign ram_rd_en   = read_allow;
    assign ram_rd_addr = raddr;
    assign rd_data     = ram_rd_data;

    wptr_full #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .ALMOST_FULL_THRESHOLD(ALMOST_FULL_THRESHOLD)
    ) u_wptr_full (
        .wclk          (wr_clk),
        .wrst_n        (wr_rstn),
        .winc          (wr_en),
        .rptr_gray_sync(rptr_gray_sync),
        .waddr         (waddr),
        .wptr_gray     (wptr_gray),
        .wfull         (full),
        .walmost_full  (almost_full),
        .wused         (wr_used)
    );

    rptr_empty #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .ALMOST_EMPTY_THRESHOLD(ALMOST_EMPTY_THRESHOLD)
    ) u_rptr_empty (
        .rclk          (rd_clk),
        .rrst_n        (rd_rstn),
        .rinc          (rd_en),
        .wptr_gray_sync(wptr_gray_sync),
        .raddr         (raddr),
        .rptr_gray     (rptr_gray),
        .rempty        (empty),
        .ralmost_empty (almost_empty),
        .rused         (rd_used)
    );

    sync_w2r #(
        .PTR_WIDTH(ADDR_WIDTH + 1)
    ) u_sync_w2r (
        .rclk           (rd_clk),
        .rrst_n         (rd_rstn),
        .wptr_gray      (wptr_gray),
        .wptr_gray_sync (wptr_gray_sync)
    );

    sync_r2w #(
        .PTR_WIDTH(ADDR_WIDTH + 1)
    ) u_sync_r2w (
        .wclk           (wr_clk),
        .wrst_n         (wr_rstn),
        .rptr_gray      (rptr_gray),
        .rptr_gray_sync (rptr_gray_sync)
    );

    always @(posedge rd_clk or negedge rd_rstn) begin
        if (!rd_rstn)
            rd_valid <= 1'b0;
        else
            rd_valid <= read_allow;
    end

    initial begin
        if (DATA_WIDTH < 1)
            $fatal(1, "DATA_WIDTH must be at least one");
        if (ADDR_WIDTH < 1)
            $fatal(1, "ADDR_WIDTH must be at least one");
        if ((ALMOST_FULL_THRESHOLD < 0) ||
            (ALMOST_FULL_THRESHOLD > (1 << ADDR_WIDTH)))
            $fatal(1, "ALMOST_FULL_THRESHOLD must be between zero and FIFO depth");
        if ((ALMOST_EMPTY_THRESHOLD < 0) ||
            (ALMOST_EMPTY_THRESHOLD > (1 << ADDR_WIDTH)))
            $fatal(1, "ALMOST_EMPTY_THRESHOLD must be between zero and FIFO depth");
    end

endmodule
