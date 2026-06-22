`timescale 1ns/1ps

// Internal equal-width FIFO implementation. Most integrations should use the
// stable rtl/async_fifo.v entry point rather than instantiate this directly.
module async_fifo_core #(
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
    output [ADDR_WIDTH:0]   rd_used
);

    // The RAM address uses ADDR_WIDTH bits. The FIFO pointers use one extra
    // wrap bit, which distinguishes an empty FIFO from a full FIFO when the
    // RAM address portions are equal.
    wire [ADDR_WIDTH-1:0] waddr;
    wire [ADDR_WIDTH-1:0] raddr;

    wire [ADDR_WIDTH:0] wptr_gray;
    wire [ADDR_WIDTH:0] rptr_gray;

    // A pointer must be synchronized into the destination clock domain before
    // it participates in empty/full comparison:
    //   wptr -> read domain for empty detection
    //   rptr -> write domain for full detection
    wire [ADDR_WIDTH:0] wptr_gray_sync;
    wire [ADDR_WIDTH:0] rptr_gray_sync;

    // These strobes represent accepted transfers. A request made while full
    // or empty does not change the RAM or the corresponding pointer.
    // Reset is destructive: no RAM access is permitted while either local
    // domain is held in reset, even if the request input remains asserted.
    // This also makes the block-RAM asynchronous-reset waiver explicit: RAM
    // contents and outputs are invalid during reset, but cannot be accessed.
    wire write_allow = wr_rstn && wr_en && !full;
    wire read_allow  = rd_rstn && rd_en && !empty;

    // Storage only.
    fifo_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_fifo_mem (
        .wclk  (wr_clk),
        .wclken(write_allow),
        .waddr (waddr),
        .wdata (wr_data),
        .rclk  (rd_clk),
        .rclken(read_allow),
        .raddr (raddr),
        .rdata (rd_data)
    );

    // Write pointer generation and full detection.
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

    // Read pointer generation and empty detection.
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

    // Write pointer synchronized into the read clock domain.
    sync_w2r #(
        .PTR_WIDTH(ADDR_WIDTH + 1)
    ) u_sync_w2r (
        .rclk           (rd_clk),
        .rrst_n         (rd_rstn),
        .wptr_gray      (wptr_gray),
        .wptr_gray_sync (wptr_gray_sync)
    );

    // Read pointer synchronized into the write clock domain.
    sync_r2w #(
        .PTR_WIDTH(ADDR_WIDTH + 1)
    ) u_sync_r2w (
        .wclk           (wr_clk),
        .wrst_n         (wr_rstn),
        .rptr_gray      (rptr_gray),
        .rptr_gray_sync (rptr_gray_sync)
    );

    // fifo_mem uses a synchronous read template. rd_valid marks an accepted
    // read request and is observed with the newly registered rd_data after
    // the same read-clock edge.
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
