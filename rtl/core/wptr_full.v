`timescale 1ns/1ps

module wptr_full #(
    parameter ADDR_WIDTH = 9,
    parameter PTR_WIDTH  = ADDR_WIDTH + 1,
    parameter ALMOST_FULL_THRESHOLD = (1 << ADDR_WIDTH) - 1
) (
    input                       wclk,
    input                       wrst_n,
    input                       winc,
    input      [PTR_WIDTH-1:0]  rptr_gray_sync,
    output     [ADDR_WIDTH-1:0] waddr,
    output reg [PTR_WIDTH-1:0]  wptr_gray,
    output reg                  wfull,
    output reg                  walmost_full,
    output reg [PTR_WIDTH-1:0]  wused
);

    // Binary form is convenient for arithmetic and RAM addressing. Gray form
    // is exported across the asynchronous clock boundary.
    reg  [PTR_WIDTH-1:0] wptr_bin;
    wire [PTR_WIDTH-1:0] wptr_bin_next;
    wire [PTR_WIDTH-1:0] wptr_gray_next;
    wire [PTR_WIDTH-1:0] rptr_bin_sync;
    wire [PTR_WIDTH-1:0] wused_next;
    wire                 wfull_next;
    wire                 walmost_full_next;

    // For a power-of-two FIFO, "one complete wrap ahead" is represented in
    // reflected Gray code by inverting the two MSBs of the read pointer while
    // leaving the remaining bits unchanged.
    localparam [PTR_WIDTH-1:0] FULL_MASK =
        {2'b11, {(PTR_WIDTH-2){1'b0}}};

    assign waddr = wptr_bin[ADDR_WIDTH-1:0];

    // Use the next pointer for full prediction, so wfull is registered in the
    // write domain and already describes whether the next write is legal.
    assign wptr_bin_next =
        wptr_bin + {{(PTR_WIDTH-1){1'b0}}, (winc && !wfull)};
    assign wptr_gray_next =
        (wptr_bin_next >> 1) ^ wptr_bin_next;
    assign rptr_bin_sync = gray_to_binary(rptr_gray_sync);
    assign wused_next = wptr_bin_next - rptr_bin_sync;
    assign wfull_next =
        (wptr_gray_next == (rptr_gray_sync ^ FULL_MASK));
    assign walmost_full_next =
        (wused_next >= ALMOST_FULL_THRESHOLD[PTR_WIDTH-1:0]);

    function [PTR_WIDTH-1:0] gray_to_binary;
        input [PTR_WIDTH-1:0] gray;
        integer i;
        begin
            gray_to_binary[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
            for (i = PTR_WIDTH-2; i >= 0; i = i - 1)
                gray_to_binary[i] =
                    gray_to_binary[i+1] ^ gray[i];
        end
    endfunction

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wptr_bin  <= {PTR_WIDTH{1'b0}};
            wptr_gray <= {PTR_WIDTH{1'b0}};
            wfull     <= 1'b0;
            walmost_full <= 1'b0;
            wused <= {PTR_WIDTH{1'b0}};
        end
        else begin
            wptr_bin  <= wptr_bin_next;
            wptr_gray <= wptr_gray_next;
            wfull     <= wfull_next;
            walmost_full <= walmost_full_next;
            wused <= wused_next;
        end
    end

endmodule
