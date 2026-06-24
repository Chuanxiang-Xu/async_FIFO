`timescale 1ns/1ps

module tb_fwft_first_word;
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

    always #3 wr_clk = ~wr_clk;
    always #5 rd_clk = ~rd_clk;

    async_fifo_fwft #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(3)
    ) dut (
        .wr_clk, .wr_rstn, .wr_en, .wr_data(wr_data), .full,
        .rd_clk, .rd_rstn, .rd_en, .rd_data(rd_data), .rd_valid, .empty
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

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        if (rd_valid || !empty)
            $fatal(1, "FWFT must reset empty with no valid output");

        write8(8'hA5);

        wait (rd_valid);
        #1;
        if (empty)
            $fatal(1, "FWFT empty must deassert when rd_valid is high");
        if (rd_data !== 8'hA5)
            $fatal(1, "FWFT first word expected A5, got %h", rd_data);

        repeat (3) begin
            @(negedge rd_clk);
            if (!rd_valid || rd_data !== 8'hA5)
                $fatal(1, "FWFT stalled first word changed or disappeared");
        end

        @(negedge rd_clk);
        rd_en = 1'b1;
        @(negedge rd_clk);
        rd_en = 1'b0;
        wait (empty);

        $display("PASS: FWFT first word appears without read request");
        $finish;
    end
endmodule

module tb_fwft_stall_and_stream;
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
    integer    i;
    integer    seen;
    reg [7:0]  expected;

    always #3 wr_clk = ~wr_clk;
    always #5 rd_clk = ~rd_clk;

    async_fifo_fwft #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(4)
    ) dut (
        .wr_clk, .wr_rstn, .wr_en, .wr_data(wr_data), .full,
        .rd_clk, .rd_rstn, .rd_en, .rd_data(rd_data), .rd_valid, .empty
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

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        for (i = 0; i < 8; i = i + 1)
            write8(8'h30 + i[7:0]);

        wait (rd_valid);
        repeat (3) begin
            @(negedge rd_clk);
            if (!rd_valid || rd_data !== 8'h30)
                $fatal(1, "FWFT output must stay stable under backpressure");
        end

        seen = 0;
        expected = 8'h30;
        if (!rd_valid || rd_data !== expected)
            $fatal(1, "FWFT stream expected first visible %h, got %h",
                   expected, rd_data);
        expected = expected + 1'b1;
        seen = seen + 1;
        rd_en = 1'b1;
        while (seen < 8) begin
            @(negedge rd_clk);
            if (rd_valid) begin
                if (rd_data !== expected)
                    $fatal(1, "FWFT stream expected %h, got %h",
                           expected, rd_data);
                expected = expected + 1'b1;
                seen = seen + 1;
            end
        end
        @(negedge rd_clk);
        rd_en = 1'b0;
        wait (empty);

        $display("PASS: FWFT stalled output and streaming order");
        $finish;
    end
endmodule

module tb_fwft_empty_pop_and_reset;
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

    always #3 wr_clk = ~wr_clk;
    always #5 rd_clk = ~rd_clk;

    async_fifo_fwft #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(3)
    ) dut (
        .wr_clk, .wr_rstn, .wr_en, .wr_data(wr_data), .full,
        .rd_clk, .rd_rstn, .rd_en, .rd_data(rd_data), .rd_valid, .empty
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

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        repeat (4) begin
            @(negedge rd_clk);
            rd_en = 1'b1;
            if (rd_valid || !empty)
                $fatal(1, "FWFT empty pop attempt must remain empty");
        end
        @(negedge rd_clk);
        rd_en = 1'b0;

        write8(8'h5A);
        wait (rd_valid);
        #1;
        if (rd_data !== 8'h5A)
            $fatal(1, "FWFT expected 5A after empty pop attempts");

        @(negedge rd_clk);
        rd_rstn = 1'b0;
        @(negedge rd_clk);
        if (rd_valid || !empty)
            $fatal(1, "FWFT read reset must clear visible output");
        rd_rstn = 1'b1;

        $display("PASS: FWFT empty pop is non-destructive and reset clears output");
        $finish;
    end
endmodule
