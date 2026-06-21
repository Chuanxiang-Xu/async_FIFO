`timescale 1ns/1ps

module sync_r2w #(
    parameter PTR_WIDTH = 10
) (
    input                      wclk,
    input                      wrst_n,
    input      [PTR_WIDTH-1:0] rptr_gray,
    output     [PTR_WIDTH-1:0] rptr_gray_sync
);

    // Two-flop synchronizer for the Gray-coded read pointer. Synchronizer
    // latency can make full conservative, but it must not permit overflow.
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] rptr_gray_meta;
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] rptr_gray_sync_reg;

    assign rptr_gray_sync = rptr_gray_sync_reg;

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            rptr_gray_meta <= {PTR_WIDTH{1'b0}};
            rptr_gray_sync_reg <= {PTR_WIDTH{1'b0}};
        end
        else begin
            rptr_gray_meta <= rptr_gray;
            rptr_gray_sync_reg <= rptr_gray_meta;
        end
    end

endmodule
