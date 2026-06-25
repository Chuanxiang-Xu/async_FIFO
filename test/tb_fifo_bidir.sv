`timescale 1ns/1ps

module tb_bidir_basic;
    reg         a_clk = 1'b0;
    reg         b_clk = 1'b0;
    reg         a_rstn = 1'b0;
    reg         b_rstn = 1'b0;

    reg         a_tx_en = 1'b0;
    reg  [7:0]  a_tx_data = 8'h00;
    wire        a_tx_full;
    wire        a_tx_almost_full;
    wire [2:0]  a_tx_used;

    reg         b_rx_en = 1'b0;
    wire [7:0]  b_rx_data;
    wire        b_rx_valid;
    wire        b_rx_empty;
    wire        b_rx_almost_empty;
    wire [2:0]  b_rx_used;

    reg         b_tx_en = 1'b0;
    reg  [7:0]  b_tx_data = 8'h00;
    wire        b_tx_full;
    wire        b_tx_almost_full;
    wire [2:0]  b_tx_used;

    reg         a_rx_en = 1'b0;
    wire [7:0]  a_rx_data;
    wire        a_rx_valid;
    wire        a_rx_empty;
    wire        a_rx_almost_empty;
    wire [2:0]  a_rx_used;

    integer i;

    always #3 a_clk = ~a_clk;
    always #5 b_clk = ~b_clk;

    async_bidir_fifo #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(2),
        .ALMOST_FULL_THRESHOLD(3),
        .ALMOST_EMPTY_THRESHOLD(1)
    ) dut (
        .a_clk,
        .a_rstn,
        .b_clk,
        .b_rstn,
        .a_tx_en,
        .a_tx_data,
        .a_tx_full,
        .a_tx_almost_full,
        .a_tx_used,
        .b_rx_en,
        .b_rx_data,
        .b_rx_valid,
        .b_rx_empty,
        .b_rx_almost_empty,
        .b_rx_used,
        .b_tx_en,
        .b_tx_data,
        .b_tx_full,
        .b_tx_almost_full,
        .b_tx_used,
        .a_rx_en,
        .a_rx_data,
        .a_rx_valid,
        .a_rx_empty,
        .a_rx_almost_empty,
        .a_rx_used
    );

    task write_a2b(input [7:0] data);
        begin
            @(negedge a_clk);
            a_tx_data = data;
            a_tx_en = 1'b1;
            @(negedge a_clk);
            a_tx_en = 1'b0;
        end
    endtask

    task write_b2a(input [7:0] data);
        begin
            @(negedge b_clk);
            b_tx_data = data;
            b_tx_en = 1'b1;
            @(negedge b_clk);
            b_tx_en = 1'b0;
        end
    endtask

    task read_b_check(input [7:0] expected);
        begin
            wait (!b_rx_empty);
            @(negedge b_clk);
            b_rx_en = 1'b1;
            @(negedge b_clk);
            b_rx_en = 1'b0;
            wait (b_rx_valid);
            #1;
            if (b_rx_data !== expected)
                $fatal(1, "A->B expected %h, got %h", expected, b_rx_data);
        end
    endtask

    task read_a_check(input [7:0] expected);
        begin
            wait (!a_rx_empty);
            @(negedge a_clk);
            a_rx_en = 1'b1;
            @(negedge a_clk);
            a_rx_en = 1'b0;
            wait (a_rx_valid);
            #1;
            if (a_rx_data !== expected)
                $fatal(1, "B->A expected %h, got %h", expected, a_rx_data);
        end
    endtask

    task simultaneous_write(input [7:0] a_data, input [7:0] b_data);
        begin
            fork
                begin
                    @(negedge a_clk);
                    a_tx_data = a_data;
                    a_tx_en = 1'b1;
                    @(negedge a_clk);
                    a_tx_en = 1'b0;
                end
                begin
                    @(negedge b_clk);
                    b_tx_data = b_data;
                    b_tx_en = 1'b1;
                    @(negedge b_clk);
                    b_tx_en = 1'b0;
                end
            join
        end
    endtask

    initial begin
        #20;
        a_rstn = 1'b1;
        b_rstn = 1'b1;

        if (!a_rx_empty || !b_rx_empty)
            $fatal(1, "bidirectional FIFO must reset both receive sides empty");

        write_a2b(8'hA1);
        read_b_check(8'hA1);

        write_b2a(8'hB1);
        read_a_check(8'hB1);

        simultaneous_write(8'hA2, 8'hB2);
        read_b_check(8'hA2);
        read_a_check(8'hB2);

        for (i = 0; i < 4; i = i + 1)
            write_a2b(8'hC0 + i[7:0]);
        wait (a_tx_full);

        if (b_tx_full)
            $fatal(1, "A->B full must not make B->A full");

        write_b2a(8'hD0);
        read_a_check(8'hD0);

        for (i = 0; i < 4; i = i + 1)
            read_b_check(8'hC0 + i[7:0]);
        wait (!a_tx_full);

        @(negedge a_clk);
        @(negedge b_clk);
        a_rstn = 1'b0;
        b_rstn = 1'b0;
        @(negedge a_clk);
        @(negedge b_clk);
        if (!a_rx_empty || !b_rx_empty || a_rx_valid || b_rx_valid)
            $fatal(1, "bidirectional FIFO reset must clear both directions");

        $display("PASS: bidirectional FIFO independent full-duplex channels");
        $finish;
    end
endmodule
