`timescale 1ns/1ps

module tb_bidir_ramif_basic;
    reg        a_clk = 1'b0;
    reg        b_clk = 1'b0;
    reg        a_rstn = 1'b0;
    reg        b_rstn = 1'b0;

    reg        a_tx_en = 1'b0;
    reg  [7:0] a_tx_data = 8'h00;
    wire       a_tx_full;
    wire       a_tx_almost_full;
    wire [2:0] a_tx_used;

    reg        b_rx_en = 1'b0;
    wire [7:0] b_rx_data;
    wire       b_rx_valid;
    wire       b_rx_empty;
    wire       b_rx_almost_empty;
    wire [2:0] b_rx_used;

    reg        b_tx_en = 1'b0;
    reg  [7:0] b_tx_data = 8'h00;
    wire       b_tx_full;
    wire       b_tx_almost_full;
    wire [2:0] b_tx_used;

    reg        a_rx_en = 1'b0;
    wire [7:0] a_rx_data;
    wire       a_rx_valid;
    wire       a_rx_empty;
    wire       a_rx_almost_empty;
    wire [2:0] a_rx_used;

    wire       a2b_ram_wr_clk;
    wire       a2b_ram_wr_en;
    wire [1:0] a2b_ram_wr_addr;
    wire [7:0] a2b_ram_wr_data;
    wire       a2b_ram_rd_clk;
    wire       a2b_ram_rd_en;
    wire [1:0] a2b_ram_rd_addr;
    reg  [7:0] a2b_ram_rd_data;

    wire       b2a_ram_wr_clk;
    wire       b2a_ram_wr_en;
    wire [1:0] b2a_ram_wr_addr;
    wire [7:0] b2a_ram_wr_data;
    wire       b2a_ram_rd_clk;
    wire       b2a_ram_rd_en;
    wire [1:0] b2a_ram_rd_addr;
    reg  [7:0] b2a_ram_rd_data;

    reg [7:0] a2b_mem [0:3];
    reg [7:0] b2a_mem [0:3];
    integer i;

    always #3 a_clk = ~a_clk;
    always #5 b_clk = ~b_clk;

    async_bidir_ramif_fifo #(
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
        .a_rx_used,
        .a2b_ram_wr_clk,
        .a2b_ram_wr_en,
        .a2b_ram_wr_addr,
        .a2b_ram_wr_data,
        .a2b_ram_rd_clk,
        .a2b_ram_rd_en,
        .a2b_ram_rd_addr,
        .a2b_ram_rd_data,
        .b2a_ram_wr_clk,
        .b2a_ram_wr_en,
        .b2a_ram_wr_addr,
        .b2a_ram_wr_data,
        .b2a_ram_rd_clk,
        .b2a_ram_rd_en,
        .b2a_ram_rd_addr,
        .b2a_ram_rd_data
    );

    always @(posedge a2b_ram_wr_clk) begin
        if (a2b_ram_wr_en)
            a2b_mem[a2b_ram_wr_addr] <= a2b_ram_wr_data;
    end

    always @(posedge a2b_ram_rd_clk) begin
        if (a2b_ram_rd_en)
            a2b_ram_rd_data <= a2b_mem[a2b_ram_rd_addr];
    end

    always @(posedge b2a_ram_wr_clk) begin
        if (b2a_ram_wr_en)
            b2a_mem[b2a_ram_wr_addr] <= b2a_ram_wr_data;
    end

    always @(posedge b2a_ram_rd_clk) begin
        if (b2a_ram_rd_en)
            b2a_ram_rd_data <= b2a_mem[b2a_ram_rd_addr];
    end

    task write_a2b(input [7:0] data);
        begin
            wait (!a_tx_full);
            @(negedge a_clk);
            a_tx_data = data;
            a_tx_en = 1'b1;
            @(negedge a_clk);
            a_tx_en = 1'b0;
        end
    endtask

    task write_b2a(input [7:0] data);
        begin
            wait (!b_tx_full);
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
                $fatal(1, "BIDIR RAMIF A->B expected %h, got %h",
                    expected, b_rx_data);
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
                $fatal(1, "BIDIR RAMIF B->A expected %h, got %h",
                    expected, a_rx_data);
        end
    endtask

    task simultaneous_write(input [7:0] a_data, input [7:0] b_data);
        begin
            fork
                write_a2b(a_data);
                write_b2a(b_data);
            join
        end
    endtask

    initial begin
        for (i = 0; i < 4; i = i + 1) begin
            a2b_mem[i] = 8'hA0 + i[7:0];
            b2a_mem[i] = 8'hB0 + i[7:0];
        end
        a2b_ram_rd_data = 8'hxx;
        b2a_ram_rd_data = 8'hxx;

        #20;
        a_rstn = 1'b1;
        b_rstn = 1'b1;

        if (!a_rx_empty || !b_rx_empty)
            $fatal(1, "BIDIR RAMIF must reset both receive sides empty");

        write_a2b(8'h11);
        read_b_check(8'h11);

        write_b2a(8'h22);
        read_a_check(8'h22);

        simultaneous_write(8'h33, 8'h44);
        read_b_check(8'h33);
        read_a_check(8'h44);

        for (i = 0; i < 4; i = i + 1)
            write_a2b(8'h50 + i[7:0]);
        wait (a_tx_full);

        if (b_tx_full)
            $fatal(1, "A->B RAMIF full must not make B->A full");

        write_b2a(8'h66);
        read_a_check(8'h66);

        for (i = 0; i < 4; i = i + 1)
            read_b_check(8'h50 + i[7:0]);

        write_a2b(8'h77);
        wait (!b_rx_empty);
        @(negedge a_clk);
        @(negedge b_clk);
        a_rstn = 1'b0;
        b_rstn = 1'b0;
        @(negedge a_clk);
        @(negedge b_clk);

        if (!a_rx_empty || !b_rx_empty || a_rx_valid || b_rx_valid)
            $fatal(1, "BIDIR RAMIF reset must clear visible control state");

        a_rstn = 1'b1;
        b_rstn = 1'b1;
        simultaneous_write(8'h88, 8'h99);
        read_b_check(8'h88);
        read_a_check(8'h99);

        $display("PASS: bidirectional RAMIF independent external-RAM channels");
        $finish;
    end
endmodule
