`timescale 1ns/1ps

module tb_async_reset_sync;
    reg  clk = 1'b0;
    reg  async_rstn = 1'b0;
    wire sync_rstn;

    always #5 clk = ~clk;

    async_reset_sync #(
        .STAGES(2)
    ) dut (
        .clk,
        .async_rstn,
        .sync_rstn
    );

    initial begin
        #7;
        if (sync_rstn !== 1'b0)
            $fatal(1, "synchronized reset must start asserted");

        // Release away from a clock edge. Two local rising edges are required.
        async_rstn = 1'b1;
        @(posedge clk);
        #1;
        if (sync_rstn !== 1'b0)
            $fatal(1, "reset released before two local clock edges");
        @(posedge clk);
        #1;
        if (sync_rstn !== 1'b1)
            $fatal(1, "reset did not release after two local clock edges");

        // Assertion is asynchronous and must not wait for another clock edge.
        #2;
        async_rstn = 1'b0;
        #1;
        if (sync_rstn !== 1'b0)
            $fatal(1, "reset assertion was not asynchronous");

        $display("PASS: async reset assertion and two-stage synchronous release");
        $finish;
    end
endmodule
