`timescale 1ns/1ps

module tb_ramif_basic;
    reg        wr_clk = 1'b0;
    reg        rd_clk = 1'b0;
    reg        wr_rstn = 1'b0;
    reg        rd_rstn = 1'b0;
    reg        wr_en = 1'b0;
    reg        rd_en = 1'b0;
    reg  [7:0] wr_data = 8'h00;

    wire       full;
    wire       almost_full;
    wire [2:0] wr_used;
    wire [7:0] rd_data;
    wire       rd_valid;
    wire       empty;
    wire       almost_empty;
    wire [2:0] rd_used;

    wire       ram_wr_clk;
    wire       ram_wr_en;
    wire [1:0] ram_wr_addr;
    wire [7:0] ram_wr_data;
    wire       ram_rd_clk;
    wire       ram_rd_en;
    wire [1:0] ram_rd_addr;
    reg  [7:0] ram_rd_data;

    reg [7:0] mem [0:3];
    integer i;

    always #3 wr_clk = ~wr_clk;
    always #5 rd_clk = ~rd_clk;

    async_fifo_ramif #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(2),
        .ALMOST_FULL_THRESHOLD(3),
        .ALMOST_EMPTY_THRESHOLD(1)
    ) dut (
        .wr_clk,
        .wr_rstn,
        .wr_en,
        .wr_data,
        .full,
        .almost_full,
        .wr_used,
        .rd_clk,
        .rd_rstn,
        .rd_en,
        .rd_data,
        .rd_valid,
        .empty,
        .almost_empty,
        .rd_used,
        .ram_wr_clk,
        .ram_wr_en,
        .ram_wr_addr,
        .ram_wr_data,
        .ram_rd_clk,
        .ram_rd_en,
        .ram_rd_addr,
        .ram_rd_data
    );

    always @(posedge ram_wr_clk) begin
        if (ram_wr_en)
            mem[ram_wr_addr] <= ram_wr_data;
    end

    always @(posedge ram_rd_clk) begin
        if (ram_rd_en)
            ram_rd_data <= mem[ram_rd_addr];
    end

    task write8(input [7:0] data);
        begin
            wait (!full);
            @(negedge wr_clk);
            wr_data = data;
            wr_en = 1'b1;
            @(negedge wr_clk);
            wr_en = 1'b0;
        end
    endtask

    task read8_check(input [7:0] expected);
        begin
            wait (!empty);
            @(negedge rd_clk);
            rd_en = 1'b1;
            @(negedge rd_clk);
            rd_en = 1'b0;
            wait (rd_valid);
            #1;
            if (rd_data !== expected)
                $fatal(1, "RAMIF expected %h, got %h", expected, rd_data);
        end
    endtask

    initial begin
        for (i = 0; i < 4; i = i + 1)
            mem[i] = 8'hE0 + i[7:0];
        ram_rd_data = 8'hxx;

        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        if (!empty)
            $fatal(1, "RAMIF must reset empty without clearing RAM");

        write8(8'h11);
        write8(8'h22);
        read8_check(8'h11);
        read8_check(8'h22);

        write8(8'h33);
        wait (!empty);
        @(negedge wr_clk);
        @(negedge rd_clk);
        wr_rstn = 1'b0;
        rd_rstn = 1'b0;
        @(negedge wr_clk);
        @(negedge rd_clk);

        if (!empty || rd_valid)
            $fatal(1, "RAMIF reset must clear pointer/control visible state");

        wr_rstn = 1'b1;
        rd_rstn = 1'b1;
        write8(8'h44);
        read8_check(8'h44);

        $display("PASS: RAMIF one-cycle external RAM contract");
        $finish;
    end
endmodule
