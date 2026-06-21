`timescale 1ns/1ps

module tb_width_conv_pack_buffer;
    reg         wr_clk = 1'b0;
    reg         rd_clk = 1'b0;
    reg         wr_rstn = 1'b0;
    reg         rd_rstn = 1'b0;
    reg         wr_en = 1'b0;
    reg         rd_en = 1'b0;
    reg  [15:0] wr_data = 16'h0000;
    wire [31:0] rd_data;
    wire        empty;
    wire        full;
    wire        almost_empty;
    wire        almost_full;
    integer     i;

    always #3 wr_clk = ~wr_clk;
    always #5 rd_clk = ~rd_clk;

    async_fifo_width_conv #(
        .WDATA_WIDTH(16),
        .RDATA_WIDTH(32),
        .ADDR_WIDTH(3)
    ) dut (
        .wr_clk(wr_clk),
        .wr_rstn(wr_rstn),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .rd_clk(rd_clk),
        .rd_rstn(rd_rstn),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .empty(empty),
        .full(full),
        .almost_empty(almost_empty),
        .almost_full(almost_full)
    );

    task write16(input [15:0] data);
        begin
            wait (!full);
            @(negedge wr_clk);
            wr_data   = data;
            wr_en = 1'b1;
            @(negedge wr_clk);
            wr_en = 1'b0;
        end
    endtask

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        // ADDR_WIDTH=3 with a 2:1 ratio gives a four-word core.
        for (i = 0; i < 8; i = i + 1)
            write16(i);

        wait (dut.core_full);

        // Even with a full core, both halves of one additional wide word can
        // be accepted into the completed-word holding register.
        write16(16'h00a0);
        if (full)
            $fatal(1, "width converter blocked before accepting final slice");
        write16(16'h00a1);
        if (!full)
            $fatal(1, "width converter did not report occupied holding slot");

        $display("PASS: width-converter completed-word buffer");
        $finish;
    end
endmodule

module tb_stream_pack_16_to_32;
    reg         wr_clk = 1'b0;
    reg         rd_clk = 1'b0;
    reg         wr_rstn = 1'b0;
    reg         rd_rstn = 1'b0;
    reg         wr_valid = 1'b0;
    wire        wr_ready;
    reg  [15:0] wr_data = 16'h0000;
    reg  [1:0]  wr_keep = 2'b00;
    reg         wr_last = 1'b0;
    wire        full;
    wire        almost_full;
    wire        rd_valid;
    reg         rd_ready = 1'b0;
    wire [31:0] rd_data;
    wire [3:0]  rd_keep;
    wire        rd_last;
    wire        empty;
    wire        almost_empty;
    reg  [31:0] held_data;
    reg  [3:0]  held_keep;
    reg         held_last;

    always #3 wr_clk = ~wr_clk;
    always #5 rd_clk = ~rd_clk;

    async_fifo_stream #(
        .WDATA_WIDTH(16),
        .RDATA_WIDTH(32),
        .ADDR_WIDTH(4)
    ) dut (
        .wr_clk, .wr_rstn, .wr_valid, .wr_ready,
        .wr_data, .wr_keep, .wr_last, .full, .almost_full,
        .rd_clk, .rd_rstn, .rd_valid, .rd_ready,
        .rd_data, .rd_keep, .rd_last, .empty, .almost_empty
    );

    task send16(
        input [15:0] data,
        input [1:0] keep,
        input       last
    );
        begin
            @(negedge wr_clk);
            wr_data  = data;
            wr_keep  = keep;
            wr_last  = last;
            wr_valid = 1'b1;
            while (!wr_ready)
                @(negedge wr_clk);
            @(negedge wr_clk);
            wr_valid = 1'b0;
        end
    endtask

    task receive32(
        input [31:0] expected_data,
        input [3:0]  expected_keep,
        input        expected_last
    );
        begin
            wait (rd_valid);
            #1;
            held_data = rd_data;
            held_keep = rd_keep;
            held_last = rd_last;

            // Exercise output backpressure and the ready/valid stability rule.
            repeat (3) begin
                @(negedge rd_clk);
                if ((rd_data !== held_data) ||
                    (rd_keep !== held_keep) ||
                    (rd_last !== held_last))
                    $fatal(1, "stream output changed while stalled");
            end

            if ((rd_data !== expected_data) ||
                (rd_keep !== expected_keep) ||
                (rd_last !== expected_last))
                $fatal(1, "stream pack mismatch data=%h keep=%b last=%b",
                       rd_data, rd_keep, rd_last);

            rd_ready = 1'b1;
            @(negedge rd_clk);
            rd_ready = 1'b0;
        end
    endtask

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        send16(16'h0001, 2'b11, 1'b0);
        send16(16'h0002, 2'b11, 1'b0);
        send16(16'h0003, 2'b11, 1'b1);

        receive32(32'h0002_0001, 4'b1111, 1'b0);
        receive32(32'h0000_0003, 4'b0011, 1'b1);

        $display("PASS: stream 16-to-32 keep/last and backpressure");
        $finish;
    end
endmodule

module tb_stream_split_32_to_16;
    reg         wr_clk = 1'b0;
    reg         rd_clk = 1'b0;
    reg         wr_rstn = 1'b0;
    reg         rd_rstn = 1'b0;
    reg         wr_valid = 1'b0;
    wire        wr_ready;
    reg  [31:0] wr_data = 32'h0000_0000;
    reg  [3:0]  wr_keep = 4'b0000;
    reg         wr_last = 1'b0;
    wire        full;
    wire        almost_full;
    wire        rd_valid;
    reg         rd_ready = 1'b0;
    wire [15:0] rd_data;
    wire [1:0]  rd_keep;
    wire        rd_last;
    wire        empty;
    wire        almost_empty;

    always #4 wr_clk = ~wr_clk;
    always #3 rd_clk = ~rd_clk;

    async_fifo_stream #(
        .WDATA_WIDTH(32),
        .RDATA_WIDTH(16),
        .ADDR_WIDTH(4)
    ) dut (
        .wr_clk, .wr_rstn, .wr_valid, .wr_ready,
        .wr_data, .wr_keep, .wr_last, .full, .almost_full,
        .rd_clk, .rd_rstn, .rd_valid, .rd_ready,
        .rd_data, .rd_keep, .rd_last, .empty, .almost_empty
    );

    task send32(
        input [31:0] data,
        input [3:0] keep,
        input       last
    );
        begin
            @(negedge wr_clk);
            wr_data  = data;
            wr_keep  = keep;
            wr_last  = last;
            wr_valid = 1'b1;
            while (!wr_ready)
                @(negedge wr_clk);
            @(negedge wr_clk);
            wr_valid = 1'b0;
        end
    endtask

    task receive16(
        input [15:0] expected_data,
        input [1:0]  expected_keep,
        input        expected_last
    );
        begin
            wait (rd_valid);
            #1;
            if ((rd_data !== expected_data) ||
                (rd_keep !== expected_keep) ||
                (rd_last !== expected_last))
                $fatal(1, "stream split mismatch data=%h keep=%b last=%b",
                       rd_data, rd_keep, rd_last);
            @(negedge rd_clk);
            rd_ready = 1'b1;
            @(negedge rd_clk);
            rd_ready = 1'b0;
        end
    endtask

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        send32(32'h1122_3344, 4'b1111, 1'b1);
        send32(32'h0000_7788, 4'b0011, 1'b1);

        receive16(16'h3344, 2'b11, 1'b0);
        receive16(16'h1122, 2'b11, 1'b1);
        receive16(16'h7788, 2'b11, 1'b1);

        $display("PASS: stream 32-to-16 keep/last");
        $finish;
    end
endmodule
