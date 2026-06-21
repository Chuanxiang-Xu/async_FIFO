`timescale 1ns/1ps

// Active-low reset synchronizer for one clock domain.
//
// async_rstn may assert asynchronously. sync_rstn remains low until STAGES
// local clock edges have safely shifted a one through the synchronizer.
// Instantiate one copy per unrelated clock domain. This module does not
// provide data-preserving runtime reset semantics for the FIFO.
module async_reset_sync #(
    parameter STAGES = 2
) (
    input  clk,
    input  async_rstn,
    output sync_rstn
);

    generate
        if (STAGES >= 2) begin : g_valid_stages
            (* ASYNC_REG = "TRUE" *) reg [STAGES-1:0] reset_pipe;

            always @(posedge clk or negedge async_rstn) begin
                if (!async_rstn)
                    reset_pipe <= {STAGES{1'b0}};
                else
                    reset_pipe <= {reset_pipe[STAGES-2:0], 1'b1};
            end

            assign sync_rstn = reset_pipe[STAGES-1];
        end
        else begin : g_invalid_stages
            assign sync_rstn = 1'b0;
            initial
            $fatal(1, "async_reset_sync STAGES must be at least two");
        end
    endgenerate

endmodule
