`timescale 1ns/1ps

module stream_assertions #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = DATA_WIDTH / 8
) (
    input                       clk,
    input                       rstn,
    input                       valid,
    input                       ready,
    input      [DATA_WIDTH-1:0] data,
    input      [KEEP_WIDTH-1:0] keep,
    input                       last
);

    logic                       stalled;
    logic [DATA_WIDTH-1:0]      stalled_data;
    logic [KEEP_WIDTH-1:0]      stalled_keep;
    logic                       stalled_last;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            stalled      <= 1'b0;
            stalled_data <= '0;
            stalled_keep <= '0;
            stalled_last <= 1'b0;
        end
        else begin
            if (stalled) begin
                assert (valid)
                    else $fatal(1, "stream valid dropped while stalled");
                assert ({data, keep, last} ===
                        {stalled_data, stalled_keep, stalled_last})
                    else $fatal(1, "stream payload changed while stalled");
            end

            stalled <= valid && !ready;
            if (valid && !ready) begin
                stalled_data <= data;
                stalled_keep <= keep;
                stalled_last <= last;
            end
        end
    end

endmodule
