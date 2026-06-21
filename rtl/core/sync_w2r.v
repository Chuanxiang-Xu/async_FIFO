`timescale 1ns/1ps

module sync_w2r #(
    parameter PTR_WIDTH = 10
) (
    input                      rclk,
    input                      rrst_n,
    input      [PTR_WIDTH-1:0] wptr_gray,
    output     [PTR_WIDTH-1:0] wptr_gray_sync
);

    // Two-flop synchronizer for the Gray-coded write pointer. ASYNC_REG helps
    // FPGA tools place and analyze the synchronizer appropriately.
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] wptr_gray_meta;
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] wptr_gray_sync_reg;

    assign wptr_gray_sync = wptr_gray_sync_reg;

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            wptr_gray_meta <= {PTR_WIDTH{1'b0}};
            wptr_gray_sync_reg <= {PTR_WIDTH{1'b0}};
        end
        else begin
            wptr_gray_meta <= wptr_gray;
            wptr_gray_sync_reg <= wptr_gray_meta;
        end
    end

endmodule
