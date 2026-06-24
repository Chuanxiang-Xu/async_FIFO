`timescale 1ns/1ps

module tb_fifo_tutorial;
    reg        wr_clk = 1'b0;
    reg        rd_clk = 1'b0;
    reg        wr_rstn = 1'b0;
    reg        rd_rstn = 1'b0;
    reg        wr_en = 1'b0;
    reg        rd_en = 1'b0;
    reg  [7:0] wr_data = 8'h00;
    wire [7:0] rd_data;
    wire       rd_valid;
    wire       empty;
    wire       full;

    always #5 wr_clk = ~wr_clk;
    always #7 rd_clk = ~rd_clk;

    async_fifo #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(2)
    ) dut (
        .wr_clk(wr_clk),
        .wr_rstn(wr_rstn),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .full(full),
        .rd_clk(rd_clk),
        .rd_rstn(rd_rstn),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .rd_valid(rd_valid),
        .empty(empty)
    );

    task write8(input [7:0] data);
        begin
            @(negedge wr_clk);
            wr_data = data;
            wr_en = 1'b1;
            @(negedge wr_clk);
            wr_en = 1'b0;
        end
    endtask

    task read8;
        begin
            @(negedge rd_clk);
            rd_en = 1'b1;
            @(negedge rd_clk);
            rd_en = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("build/tutorial_async_fifo.vcd");
        $dumpvars(0, tb_fifo_tutorial);

        #24;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        write8(8'hA0);
        write8(8'hA1);
        write8(8'hA2);
        write8(8'hA3);

        @(negedge wr_clk);
        wr_data = 8'hEE;
        wr_en = 1'b1;
        repeat (2) @(negedge wr_clk);
        wr_en = 1'b0;

        wait (!empty);
        read8();
        read8();

        repeat (6) @(posedge rd_clk);
        $finish;
    end
endmodule
