`timescale 1ns/1ps

module rptr_empty #(
    parameter ADDR_WIDTH = 9,
    parameter PTR_WIDTH  = ADDR_WIDTH + 1,
    parameter ALMOST_EMPTY_THRESHOLD = 1
) (
    input                       rclk,
    input                       rrst_n,
    input                       rinc,
    input      [PTR_WIDTH-1:0]  wptr_gray_sync,
    output     [ADDR_WIDTH-1:0] raddr,
    output reg [PTR_WIDTH-1:0]  rptr_gray,
    output reg                  rempty,
    output reg                  ralmost_empty,
    output reg [PTR_WIDTH-1:0]  rused
);

    // Binary form drives the RAM address; Gray form is safe to synchronize.
    reg  [PTR_WIDTH-1:0] rptr_bin;
    wire [PTR_WIDTH-1:0] rptr_bin_next;
    wire [PTR_WIDTH-1:0] rptr_gray_next;
    wire [PTR_WIDTH-1:0] wptr_bin_sync;
    wire [PTR_WIDTH-1:0] rused_next;
    wire                 rempty_next;
    wire                 ralmost_empty_next;

    assign raddr = rptr_bin[ADDR_WIDTH-1:0];

    // Empty is predicted from the next accepted read pointer. Equality with
    // the synchronized write pointer means no unread words remain.
    assign rptr_bin_next =
        rptr_bin + {{(PTR_WIDTH-1){1'b0}}, (rinc && !rempty)};
    assign rptr_gray_next =
        (rptr_bin_next >> 1) ^ rptr_bin_next;
    assign wptr_bin_sync = gray_to_binary(wptr_gray_sync);
    assign rused_next = wptr_bin_sync - rptr_bin_next;
    assign rempty_next = (rptr_gray_next == wptr_gray_sync);
    assign ralmost_empty_next =
        (rused_next <= ALMOST_EMPTY_THRESHOLD);

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

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rptr_bin  <= {PTR_WIDTH{1'b0}};
            rptr_gray <= {PTR_WIDTH{1'b0}};
            rempty    <= 1'b1;
            ralmost_empty <= 1'b1;
            rused <= {PTR_WIDTH{1'b0}};
        end
        else begin
            rptr_bin  <= rptr_bin_next;
            rptr_gray <= rptr_gray_next;
            rempty    <= rempty_next;
            ralmost_empty <= ralmost_empty_next;
            rused <= rused_next;
        end
    end

endmodule
