`timescale 1ns/1ps

module tb_equal_width;
    reg         wr_clk = 1'b0;
    reg         rd_clk = 1'b0;
    reg         wr_rstn = 1'b0;
    reg         rd_rstn = 1'b0;
    reg         wr_en = 1'b0;
    reg         rd_en = 1'b0;
    reg  [31:0] wr_data = 32'h0000_0000;
    wire [31:0] rd_data;
    wire        rd_valid;
    wire        empty;
    wire        full;

    always #3 wr_clk = ~wr_clk;
    always #5 rd_clk = ~rd_clk;

    async_fifo #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(4)
    ) dut (
        .wr_clk, .wr_rstn, .wr_en, .wr_data(wr_data), .full,
        .rd_clk, .rd_rstn, .rd_en, .rd_data(rd_data), .rd_valid, .empty
    );

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        @(negedge wr_clk);
        wr_data   = 32'hCAFE_BABE;
        wr_en = 1'b1;
        @(negedge wr_clk);
        wr_en = 1'b0;

        wait (!empty);
        @(negedge rd_clk);
        rd_en = 1'b1;
        @(negedge rd_clk);
        rd_en = 1'b0;

        wait (rd_valid);
        #1;
        if (rd_data !== 32'hCAFE_BABE)
            $fatal(1, "equal-width expected CAFE_BABE, got %h", rd_data);

        $display("PASS: parameterized equal-width FIFO");
        $finish;
    end
endmodule

module tb_almost_flags;
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
    wire       almost_empty;
    wire       full;
    wire       almost_full;
    integer    i;

    always #3 wr_clk = ~wr_clk;
    always #5 rd_clk = ~rd_clk;

    async_fifo #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(3),
        .ALMOST_FULL_THRESHOLD(6),
        .ALMOST_EMPTY_THRESHOLD(2)
    ) dut (
        .wr_clk(wr_clk),
        .wr_rstn(wr_rstn),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .full(full),
        .almost_full(almost_full),
        .rd_clk(rd_clk),
        .rd_rstn(rd_rstn),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .rd_valid(rd_valid),
        .empty(empty),
        .almost_empty(almost_empty)
    );

    task write8(input [7:0] data);
        begin
            @(negedge wr_clk);
            wr_data   = data;
            wr_en = 1'b1;
            @(negedge wr_clk);
            wr_en = 1'b0;
        end
    endtask

    task read8;
        begin
            wait (!empty);
            @(negedge rd_clk);
            rd_en = 1'b1;
            @(negedge rd_clk);
            rd_en = 1'b0;
            wait (rd_valid);
        end
    endtask

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        if (!almost_empty)
            $fatal(1, "almost_empty must be set after reset");

        for (i = 0; i < 5; i = i + 1)
            write8(i);

        if (almost_full)
            $fatal(1, "almost_full asserted below its threshold");

        write8(8'h05);
        wait (almost_full);
        wait (!almost_empty);

        for (i = 0; i < 4; i = i + 1)
            read8();

        wait (almost_empty);
        wait (!almost_full);

        $display("PASS: programmable almost-full/almost-empty flags");
        $finish;
    end
endmodule

module tb_pack_16_to_32;
    reg         wr_clk = 1'b0;
    reg         rd_clk = 1'b0;
    reg         wr_rstn = 1'b0;
    reg         rd_rstn = 1'b0;
    reg         wr_en = 1'b0;
    reg         rd_en = 1'b0;
    reg  [15:0] wr_data = 16'h0000;
    wire [31:0] rd_data;
    wire        rd_valid;
    wire        empty;
    wire        full;

    always #3 wr_clk = ~wr_clk;
    always #5 rd_clk = ~rd_clk;

    async_fifo_width_conv #(
        .WDATA_WIDTH(16),
        .RDATA_WIDTH(32),
        .ADDR_WIDTH (4)
    ) dut (
        .wr_clk, .wr_rstn, .wr_en, .wr_data(wr_data),
        .rd_clk, .rd_rstn, .rd_en, .rd_data(rd_data),
        .rd_valid, .empty, .full
    );

    task write16(input [15:0] data);
        begin
            @(negedge wr_clk);
            wr_data   = data;
            wr_en = 1'b1;
            @(negedge wr_clk);
            wr_en = 1'b0;
        end
    endtask

    task read32_check(input [31:0] expected);
        begin
            wait (!empty);
            @(negedge rd_clk);
            rd_en = 1'b1;
            @(negedge rd_clk);
            rd_en = 1'b0;
            wait (rd_valid);
            #1;
            if (rd_data !== expected)
                $fatal(1, "16->32 expected %h, got %h", expected, rd_data);
        end
    endtask

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        write16(16'h0001);
        write16(16'h0002);
        write16(16'h0003);
        write16(16'h0004);

        read32_check(32'h0002_0001);
        read32_check(32'h0004_0003);

        $display("PASS: 16-bit write to 32-bit read");
        $finish;
    end
endmodule

module tb_split_32_to_16;
    reg         wr_clk = 1'b0;
    reg         rd_clk = 1'b0;
    reg         wr_rstn = 1'b0;
    reg         rd_rstn = 1'b0;
    reg         wr_en = 1'b0;
    reg         rd_en = 1'b0;
    reg  [31:0] wr_data = 32'h0000_0000;
    wire [15:0] rd_data;
    wire        rd_valid;
    wire        empty;
    wire        full;

    always #3 wr_clk = ~wr_clk;
    always #5 rd_clk = ~rd_clk;

    async_fifo_width_conv #(
        .WDATA_WIDTH(32),
        .RDATA_WIDTH(16),
        .ADDR_WIDTH (4)
    ) dut (
        .wr_clk, .wr_rstn, .wr_en, .wr_data(wr_data),
        .rd_clk, .rd_rstn, .rd_en, .rd_data(rd_data),
        .rd_valid, .empty, .full
    );

    task write32(input [31:0] data);
        begin
            @(negedge wr_clk);
            wr_data   = data;
            wr_en = 1'b1;
            @(negedge wr_clk);
            wr_en = 1'b0;
        end
    endtask

    task request_first16_check(input [15:0] expected);
        begin
            wait (!empty);
            @(negedge rd_clk);
            rd_en = 1'b1;
            @(negedge rd_clk);
            rd_en = 1'b0;
            wait (rd_valid);
            #1;
            if (rd_data !== expected)
                $fatal(1, "32->16 first expected %h, got %h", expected, rd_data);
        end
    endtask

    task read_buffered16_check(input [15:0] expected);
        begin
            @(negedge rd_clk);
            rd_en = 1'b1;
            @(negedge rd_clk);
            rd_en = 1'b0;
            wait (rd_valid);
            #1;
            if (rd_data !== expected)
                $fatal(1, "32->16 expected %h, got %h", expected, rd_data);
        end
    endtask

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        write32(32'h1122_3344);
        write32(32'h5566_7788);

        request_first16_check(16'h3344);
        read_buffered16_check(16'h1122);
        request_first16_check(16'h7788);
        read_buffered16_check(16'h5566);

        $display("PASS: 32-bit write to 16-bit read");
        $finish;
    end
endmodule
