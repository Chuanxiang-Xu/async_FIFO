`timescale 1ns/1ps

module tb_fifo_boundary;
    localparam DATA_WIDTH = 8;
    localparam ADDR_WIDTH = 3;
    localparam DEPTH = 1 << ADDR_WIDTH;

    logic                  wr_clk = 1'b0;
    logic                  rd_clk = 1'b0;
    logic                  wr_rstn = 1'b0;
    logic                  rd_rstn = 1'b0;
    logic                  wr_en = 1'b0;
    logic                  rd_en = 1'b0;
    logic [DATA_WIDTH-1:0] wr_data = '0;
    wire  [DATA_WIDTH-1:0] rd_data;
    wire                   rd_valid;
    wire                   full;
    wire                   almost_full;
    wire                   empty;
    wire                   almost_empty;
    wire  [ADDR_WIDTH:0]   wr_used;
    wire  [ADDR_WIDTH:0]   rd_used;
    integer                i;
    integer                expected;

    always #3 wr_clk = ~wr_clk;
    always #5 rd_clk = ~rd_clk;

    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk, .wr_rstn, .wr_en, .wr_data(wr_data),
        .full, .almost_full, .wr_used,
        .rd_clk, .rd_rstn, .rd_en, .rd_data(rd_data), .rd_valid,
        .empty, .almost_empty, .rd_used
    );

    fifo_assertions #(
        .PTR_WIDTH(ADDR_WIDTH + 1)
    ) assertions (
        .wr_clk,
        .wr_rstn,
        .wr_request(wr_en),
        .full,
        .wptr_gray(dut.u_async_fifo_core.wptr_gray),
        .rd_clk,
        .rd_rstn,
        .rd_request(rd_en),
        .empty,
        .rptr_gray(dut.u_async_fifo_core.rptr_gray)
    );

    task automatic write_word(input logic [DATA_WIDTH-1:0] value);
        begin
            wait (!full);
            @(negedge wr_clk);
            wr_data   = value;
            wr_en = 1'b1;
            @(negedge wr_clk);
            wr_en = 1'b0;
        end
    endtask

    task automatic read_check(input logic [DATA_WIDTH-1:0] value);
        begin
            wait (!empty);
            @(negedge rd_clk);
            rd_en = 1'b1;
            @(negedge rd_clk);
            rd_en = 1'b0;
            wait (rd_valid);
            #1;
            assert (rd_data === value)
                else $fatal(1, "boundary expected %h, got %h", value, rd_data);
        end
    endtask

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        // Fill exactly to full and attempt blocked writes.
        for (i = 0; i < DEPTH; i = i + 1)
            write_word(i);
        wait (full);
        assert (wr_used == DEPTH)
            else $fatal(1, "wr_used did not report full depth");

        @(negedge wr_clk);
        wr_en = 1'b1;
        wr_data = 8'hee;
        repeat (3) @(negedge wr_clk);
        wr_en = 1'b0;

        // Drain and attempt blocked reads.
        for (i = 0; i < DEPTH; i = i + 1)
            read_check(i);
        wait (empty);
        assert (rd_used == 0)
            else $fatal(1, "rd_used did not report empty");

        @(negedge rd_clk);
        rd_en = 1'b1;
        repeat (3) @(negedge rd_clk);
        rd_en = 1'b0;

        // More than four complete depths guarantees repeated pointer wrap.
        expected = 8'h40;
        for (i = 0; i < (DEPTH * 5); i = i + 1) begin
            write_word((8'h40 + i) & 8'hff);
            read_check((8'h40 + i) & 8'hff);
        end

        $display("PASS: full, empty, blocked access, occupancy, and wraparound");
        $finish;
    end
endmodule

module tb_reset_access_gate;
    localparam DATA_WIDTH = 8;
    localparam ADDR_WIDTH = 2;

    logic                  wr_clk = 1'b0;
    logic                  rd_clk = 1'b0;
    logic                  wr_rstn = 1'b0;
    logic                  rd_rstn = 1'b0;
    logic                  wr_en = 1'b1;
    logic                  rd_en = 1'b1;
    logic [DATA_WIDTH-1:0] wr_data = 8'h5a;
    wire  [DATA_WIDTH-1:0] rd_data;
    wire                   rd_valid;
    wire                   full;
    wire                   almost_full;
    wire                   empty;
    wire                   almost_empty;
    wire  [ADDR_WIDTH:0]   wr_used;
    wire  [ADDR_WIDTH:0]   rd_used;

    always #3 wr_clk = ~wr_clk;
    always #5 rd_clk = ~rd_clk;

    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk, .wr_rstn, .wr_en, .wr_data,
        .full, .almost_full, .wr_used,
        .rd_clk, .rd_rstn, .rd_en, .rd_data, .rd_valid,
        .empty, .almost_empty, .rd_used
    );

    always @(posedge wr_clk) begin
        if (!wr_rstn)
            assert (!dut.u_async_fifo_core.write_allow)
                else $fatal(1, "RAM write enabled during write reset");
    end

    always @(posedge rd_clk) begin
        #1;
        if (!rd_rstn) begin
            assert (!dut.u_async_fifo_core.read_allow)
                else $fatal(1, "RAM read enabled during read reset");
            assert (!rd_valid)
                else $fatal(1, "rd_valid asserted during read reset");
        end
    end

    initial begin
        // Requests deliberately remain asserted throughout reset.
        repeat (4) @(posedge wr_clk);
        assert (dut.u_async_fifo_core.u_wptr_full.wptr_bin == 0)
            else $fatal(1, "write pointer moved during reset");
        assert (dut.u_async_fifo_core.u_rptr_empty.rptr_bin == 0)
            else $fatal(1, "read pointer moved during reset");

        wr_en = 1'b0;
        rd_en = 1'b0;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        // Confirm normal operation resumes after coordinated reset release.
        @(negedge wr_clk);
        wr_data = 8'ha5;
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
        assert (rd_data == 8'ha5)
            else $fatal(1, "post-reset transfer mismatch");

        $display("PASS: reset blocks RAM access and normal transfer resumes");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "reset access-gate test timed out");
    end
endmodule

module tb_stream_write_throughput;
    localparam ITEM_COUNT = 32;

    logic        wr_clk = 1'b0;
    logic        rd_clk = 1'b0;
    logic        wr_rstn = 1'b0;
    logic        rd_rstn = 1'b0;
    logic        wr_valid = 1'b0;
    wire         wr_ready;
    logic [31:0] wr_data = '0;
    logic [3:0]  wr_keep = 4'hf;
    logic        wr_last = 1'b0;
    wire         rd_valid;
    logic        rd_ready = 1'b1;
    wire [31:0]  rd_data;
    wire [3:0]   rd_keep;
    wire         rd_last;
    wire         full;
    wire         almost_full;
    wire         empty;
    wire         almost_empty;
    wire [6:0]   wr_used;
    wire [6:0]   rd_used;
    integer      i;
    integer      received = 0;

    always #2 wr_clk = ~wr_clk;
    always #3 rd_clk = ~rd_clk;

    async_fifo_stream #(
        .WDATA_WIDTH(32),
        .RDATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) dut (
        .wr_clk, .wr_rstn, .wr_valid, .wr_ready,
        .wr_data, .wr_keep, .wr_last,
        .full, .almost_full, .wr_core_used(wr_used),
        .rd_clk, .rd_rstn, .rd_valid, .rd_ready,
        .rd_data, .rd_keep, .rd_last,
        .empty, .almost_empty, .rd_core_used(rd_used)
    );

    always @(posedge rd_clk) begin
        if (rd_rstn && rd_valid && rd_ready) begin
            assert (rd_data == received)
                else $fatal(1,
                    "throughput sequence mismatch expected=%0d got=%0d",
                    received, rd_data);
            received = received + 1;
        end
    end

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        // Present one new beat on every write clock. With an elastic pending
        // register, wr_ready must remain asserted while the core has space.
        for (i = 0; i < ITEM_COUNT; i = i + 1) begin
            @(negedge wr_clk);
            assert (wr_ready)
                else $fatal(1, "unexpected write bubble at item %0d", i);
            wr_valid = 1'b1;
            wr_data  = i;
            wr_keep  = 4'hf;
            wr_last  = (i == ITEM_COUNT - 1);
        end
        @(negedge wr_clk);
        wr_valid = 1'b0;

        wait (received == ITEM_COUNT);
        $display("PASS: stream accepts one write beat per clock without bubbles");
        $finish;
    end
endmodule

module tb_stream_read_throughput;
    localparam ITEM_COUNT = 32;

    logic        wr_clk = 1'b0;
    logic        rd_clk = 1'b0;
    logic        wr_rstn = 1'b0;
    logic        rd_rstn = 1'b0;
    logic        wr_valid = 1'b0;
    wire         wr_ready;
    logic [31:0] wr_data = '0;
    logic [3:0]  wr_keep = 4'hf;
    logic        wr_last = 1'b0;
    wire         rd_valid;
    logic        rd_ready = 1'b0;
    wire [31:0]  rd_data;
    wire [3:0]   rd_keep;
    wire         rd_last;
    wire         full;
    wire         almost_full;
    wire         empty;
    wire         almost_empty;
    integer      i;
    integer      received = 0;
    logic        drain_started = 1'b0;

    always #3 wr_clk = ~wr_clk;
    always #2 rd_clk = ~rd_clk;

    async_fifo_stream #(
        .WDATA_WIDTH(32),
        .RDATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) dut (
        .wr_clk, .wr_rstn, .wr_valid, .wr_ready,
        .wr_data, .wr_keep, .wr_last,
        .full, .almost_full,
        .rd_clk, .rd_rstn, .rd_valid, .rd_ready,
        .rd_data, .rd_keep, .rd_last,
        .empty, .almost_empty
    );

    always @(posedge rd_clk) begin
        if (drain_started && received < ITEM_COUNT) begin
            assert (rd_valid)
                else $fatal(1, "equal-width read prefetch inserted a bubble");
            assert (rd_data == received)
                else $fatal(1, "read throughput sequence mismatch");
            received = received + 1;
        end
    end

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        for (i = 0; i < ITEM_COUNT; i = i + 1) begin
            @(negedge wr_clk);
            wr_valid = 1'b1;
            wr_data = i;
            wr_last = (i == ITEM_COUNT - 1);
            while (!wr_ready)
                @(negedge wr_clk);
        end
        @(negedge wr_clk);
        wr_valid = 1'b0;

        // Let both local read slots fill before starting a continuous drain.
        wait (dut.out_valid && dut.next_valid);
        @(negedge rd_clk);
        rd_ready = 1'b1;
        drain_started = 1'b1;

        wait (received == ITEM_COUNT);
        $display("PASS: stream produces one equal-width read beat per clock");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "equal-width read throughput test timed out");
    end
endmodule

module tb_stream_split_read_throughput;
    localparam INPUT_WORDS = 16;
    localparam OUTPUT_BEATS = INPUT_WORDS * 2;

    logic        wr_clk = 1'b0;
    logic        rd_clk = 1'b0;
    logic        wr_rstn = 1'b0;
    logic        rd_rstn = 1'b0;
    logic        wr_valid = 1'b0;
    wire         wr_ready;
    logic [31:0] wr_data = '0;
    logic [3:0]  wr_keep = 4'hf;
    logic        wr_last = 1'b1;
    wire         rd_valid;
    logic        rd_ready = 1'b0;
    wire [15:0]  rd_data;
    wire [1:0]   rd_keep;
    wire         rd_last;
    wire         full;
    wire         almost_full;
    wire         empty;
    wire         almost_empty;
    integer      i;
    integer      received = 0;
    logic        drain_started = 1'b0;

    always #3 wr_clk = ~wr_clk;
    always #2 rd_clk = ~rd_clk;

    async_fifo_stream #(
        .WDATA_WIDTH(32),
        .RDATA_WIDTH(16),
        .ADDR_WIDTH(6)
    ) dut (
        .wr_clk, .wr_rstn, .wr_valid, .wr_ready,
        .wr_data, .wr_keep, .wr_last,
        .full, .almost_full,
        .rd_clk, .rd_rstn, .rd_valid, .rd_ready,
        .rd_data, .rd_keep, .rd_last,
        .empty, .almost_empty
    );

    always @(posedge rd_clk) begin
        if (drain_started && received < OUTPUT_BEATS) begin
            assert (rd_valid)
                else $fatal(1, "split read prefetch inserted a bubble");
            assert (rd_data == received[15:0])
                else $fatal(1, "split throughput sequence mismatch");
            assert (rd_keep == 2'b11)
                else $fatal(1, "split throughput keep mismatch");
            assert (rd_last == received[0])
                else $fatal(1, "split throughput last mismatch");
            received = received + 1;
        end
    end

    initial begin
        #20;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        for (i = 0; i < INPUT_WORDS; i = i + 1) begin
            @(negedge wr_clk);
            wr_valid = 1'b1;
            wr_data[15:0] = 2*i;
            wr_data[31:16] = (2*i)+1;
            while (!wr_ready)
                @(negedge wr_clk);
        end
        @(negedge wr_clk);
        wr_valid = 1'b0;

        wait (dut.out_valid && dut.next_valid);
        @(negedge rd_clk);
        rd_ready = 1'b1;
        drain_started = 1'b1;

        wait (received == OUTPUT_BEATS);
        $display("PASS: stream produces one split read beat per clock");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "split read throughput test timed out");
    end
endmodule

module tb_stream_random_pack_16_to_32;
    localparam INPUT_BEATS = 800;
    localparam MAX_OUTPUTS = INPUT_BEATS;

    logic        wr_clk = 1'b0;
    logic        rd_clk = 1'b0;
    logic        wr_rstn = 1'b0;
    logic        rd_rstn = 1'b0;
    logic        wr_valid = 1'b0;
    wire         wr_ready;
    logic [15:0] wr_data = '0;
    logic [1:0]  wr_keep = '0;
    logic        wr_last = 1'b0;
    wire         rd_valid;
    logic        rd_ready = 1'b0;
    wire [31:0]  rd_data;
    wire [3:0]   rd_keep;
    wire         rd_last;
    wire         full;
    wire         almost_full;
    wire         empty;
    wire         almost_empty;
    wire [6:0]   wr_used;
    wire [6:0]   rd_used;

    logic [31:0] expected_data [0:MAX_OUTPUTS-1];
    logic [3:0]  expected_keep [0:MAX_OUTPUTS-1];
    logic        expected_last [0:MAX_OUTPUTS-1];
    logic [15:0] model_low_data = '0;
    logic [1:0]  model_low_keep = '0;
    integer      model_count = 0;
    integer      expected_push = 0;
    integer      expected_pop = 0;
    integer      produced = 0;
    integer      packet_length;
    integer      packet_index;
    integer      gap;
    integer      seed = 32'h16a0325a;
    logic        producer_done = 1'b0;

    always #2.5 wr_clk = ~wr_clk;
    always #4.5 rd_clk = ~rd_clk;

    async_fifo_stream #(
        .WDATA_WIDTH(16),
        .RDATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) dut (
        .wr_clk, .wr_rstn, .wr_valid, .wr_ready,
        .wr_data, .wr_keep, .wr_last,
        .full, .almost_full, .wr_core_used(wr_used),
        .rd_clk, .rd_rstn, .rd_valid, .rd_ready,
        .rd_data, .rd_keep, .rd_last,
        .empty, .almost_empty, .rd_core_used(rd_used)
    );

    stream_assertions #(.DATA_WIDTH(32), .KEEP_WIDTH(4)) protocol (
        .clk(rd_clk), .rstn(rd_rstn), .valid(rd_valid), .ready(rd_ready),
        .data(rd_data), .keep(rd_keep), .last(rd_last)
    );

    always @(negedge rd_clk) begin
        if (!rd_rstn)
            rd_ready <= 1'b0;
        else if (producer_done)
            rd_ready <= 1'b1;
        else
            rd_ready <= (($urandom(seed) % 100) < 63);
    end

    always @(posedge rd_clk) begin
        if (rd_rstn && rd_valid && rd_ready) begin
            assert (expected_pop < expected_push)
                else $fatal(1, "16->32 produced unexpected output");
            assert ({rd_data, rd_keep, rd_last} ===
                    {expected_data[expected_pop], expected_keep[expected_pop],
                     expected_last[expected_pop]})
                else $fatal(1, "16->32 random mismatch at %0d", expected_pop);
            expected_pop = expected_pop + 1;
        end
    end

    initial begin
        #30;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        while (produced < INPUT_BEATS) begin
            packet_length = ($urandom(seed) % 7) + 1;
            if (packet_length > INPUT_BEATS - produced)
                packet_length = INPUT_BEATS - produced;

            for (packet_index = 0;
                 packet_index < packet_length;
                 packet_index = packet_index + 1) begin
                gap = $urandom(seed) % 3;
                repeat (gap) @(negedge wr_clk);

                @(negedge wr_clk);
                wr_data  = $urandom(seed);
                wr_last  = (packet_index == packet_length - 1);
                wr_keep  = (wr_last && (($urandom(seed) & 1) == 0)) ?
                           2'b01 : 2'b11;
                wr_valid = 1'b1;
                while (!wr_ready)
                    @(negedge wr_clk);
                @(negedge wr_clk);
                wr_valid = 1'b0;

                if (model_count == 0) begin
                    if (wr_last) begin
                        expected_data[expected_push] = {16'b0, wr_data};
                        expected_keep[expected_push] = {2'b00, wr_keep};
                        expected_last[expected_push] = 1'b1;
                        expected_push = expected_push + 1;
                    end
                    else begin
                        model_low_data = wr_data;
                        model_low_keep = wr_keep;
                        model_count = 1;
                    end
                end
                else begin
                    expected_data[expected_push] = {wr_data, model_low_data};
                    expected_keep[expected_push] = {wr_keep, model_low_keep};
                    expected_last[expected_push] = wr_last;
                    expected_push = expected_push + 1;
                    model_count = 0;
                end
                produced = produced + 1;
            end
        end

        producer_done = 1'b1;
        wait ((expected_pop == expected_push) && empty && !rd_valid);
        assert (model_count == 0)
            else $fatal(1, "16->32 model ended with an incomplete word");
        $display("PASS: randomized stream 16-to-32 width conversion (%0d outputs)",
                 expected_pop);
        $finish;
    end

    initial begin
        #3000000;
        $fatal(1, "random 16-to-32 stream test timed out");
    end
endmodule

module tb_stream_random_split_32_to_16;
    localparam INPUT_BEATS = 500;
    localparam MAX_OUTPUTS = INPUT_BEATS * 2;

    logic        wr_clk = 1'b0;
    logic        rd_clk = 1'b0;
    logic        wr_rstn = 1'b0;
    logic        rd_rstn = 1'b0;
    logic        wr_valid = 1'b0;
    wire         wr_ready;
    logic [31:0] wr_data = '0;
    logic [3:0]  wr_keep = '0;
    logic        wr_last = 1'b0;
    wire         rd_valid;
    logic        rd_ready = 1'b0;
    wire [15:0]  rd_data;
    wire [1:0]   rd_keep;
    wire         rd_last;
    wire         full;
    wire         almost_full;
    wire         empty;
    wire         almost_empty;
    wire [6:0]   wr_used;
    wire [6:0]   rd_used;

    logic [15:0] expected_data [0:MAX_OUTPUTS-1];
    logic [1:0]  expected_keep [0:MAX_OUTPUTS-1];
    logic        expected_last [0:MAX_OUTPUTS-1];
    integer      expected_push = 0;
    integer      expected_pop = 0;
    integer      produced = 0;
    integer      packet_length;
    integer      packet_index;
    integer      gap;
    integer      seed = 32'h32b016c3;
    logic        producer_done = 1'b0;

    always #3.5 wr_clk = ~wr_clk;
    always #2.5 rd_clk = ~rd_clk;

    async_fifo_stream #(
        .WDATA_WIDTH(32),
        .RDATA_WIDTH(16),
        .ADDR_WIDTH(6)
    ) dut (
        .wr_clk, .wr_rstn, .wr_valid, .wr_ready,
        .wr_data, .wr_keep, .wr_last,
        .full, .almost_full, .wr_core_used(wr_used),
        .rd_clk, .rd_rstn, .rd_valid, .rd_ready,
        .rd_data, .rd_keep, .rd_last,
        .empty, .almost_empty, .rd_core_used(rd_used)
    );

    stream_assertions #(.DATA_WIDTH(16), .KEEP_WIDTH(2)) protocol (
        .clk(rd_clk), .rstn(rd_rstn), .valid(rd_valid), .ready(rd_ready),
        .data(rd_data), .keep(rd_keep), .last(rd_last)
    );

    always @(negedge rd_clk) begin
        if (!rd_rstn)
            rd_ready <= 1'b0;
        else if (producer_done)
            rd_ready <= 1'b1;
        else
            rd_ready <= (($urandom(seed) % 100) < 59);
    end

    always @(posedge rd_clk) begin
        if (rd_rstn && rd_valid && rd_ready) begin
            assert (expected_pop < expected_push)
                else $fatal(1, "32->16 produced unexpected output");
            assert ({rd_data, rd_keep, rd_last} ===
                    {expected_data[expected_pop], expected_keep[expected_pop],
                     expected_last[expected_pop]})
                else $fatal(1, "32->16 random mismatch at %0d", expected_pop);
            expected_pop = expected_pop + 1;
        end
    end

    initial begin
        #30;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        while (produced < INPUT_BEATS) begin
            packet_length = ($urandom(seed) % 6) + 1;
            if (packet_length > INPUT_BEATS - produced)
                packet_length = INPUT_BEATS - produced;

            for (packet_index = 0;
                 packet_index < packet_length;
                 packet_index = packet_index + 1) begin
                gap = $urandom(seed) % 3;
                repeat (gap) @(negedge wr_clk);

                @(negedge wr_clk);
                wr_data  = $urandom(seed);
                wr_last  = (packet_index == packet_length - 1);
                wr_keep  = (wr_last && (($urandom(seed) & 1) == 0)) ?
                           4'b0011 : 4'b1111;
                wr_valid = 1'b1;
                while (!wr_ready)
                    @(negedge wr_clk);
                @(negedge wr_clk);
                wr_valid = 1'b0;

                expected_data[expected_push] = wr_data[15:0];
                expected_keep[expected_push] = wr_keep[1:0];
                expected_last[expected_push] = wr_last &&
                                               (wr_keep[3:2] == 2'b00);
                expected_push = expected_push + 1;

                if (wr_keep[3:2] != 2'b00) begin
                    expected_data[expected_push] = wr_data[31:16];
                    expected_keep[expected_push] = wr_keep[3:2];
                    expected_last[expected_push] = wr_last;
                    expected_push = expected_push + 1;
                end
                produced = produced + 1;
            end
        end

        producer_done = 1'b1;
        wait ((expected_pop == expected_push) && empty && !rd_valid);
        $display("PASS: randomized stream 32-to-16 width conversion (%0d outputs)",
                 expected_pop);
        $finish;
    end

    initial begin
        #3000000;
        $fatal(1, "random 32-to-16 stream test timed out");
    end
endmodule

module tb_stream_random;
    localparam DATA_WIDTH = 16;
    localparam KEEP_WIDTH = DATA_WIDTH / 8;
    localparam ADDR_WIDTH = 4;
    localparam ITEM_COUNT = 1200;

    logic                    wr_clk = 1'b0;
    logic                    rd_clk = 1'b0;
    logic                    wr_rstn = 1'b0;
    logic                    rd_rstn = 1'b0;
    logic                    wr_valid = 1'b0;
    wire                     wr_ready;
    logic [DATA_WIDTH-1:0]   wr_data = '0;
    logic [KEEP_WIDTH-1:0]   wr_keep = '0;
    logic                    wr_last = 1'b0;
    wire                     full;
    wire                     almost_full;
    wire [ADDR_WIDTH:0]      wr_used;
    wire                     rd_valid;
    logic                    rd_ready = 1'b0;
    wire [DATA_WIDTH-1:0]    rd_data;
    wire [KEEP_WIDTH-1:0]    rd_keep;
    wire                     rd_last;
    wire                     empty;
    wire                     almost_empty;
    wire [ADDR_WIDTH:0]      rd_used;

    logic [DATA_WIDTH-1:0] expected_data [0:ITEM_COUNT-1];
    logic [KEEP_WIDTH-1:0] expected_keep [0:ITEM_COUNT-1];
    logic                  expected_last [0:ITEM_COUNT-1];
    integer push_index = 0;
    integer pop_index = 0;
    integer generated = 0;
    integer packet_remaining = 0;
    integer seed = 32'h13579bdf;
    logic producer_done = 1'b0;

    always #2.5 wr_clk = ~wr_clk;  // 5 ns
    always #6.5 rd_clk = ~rd_clk;  // 13 ns

    async_fifo_stream #(
        .WDATA_WIDTH(DATA_WIDTH),
        .RDATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk, .wr_rstn, .wr_valid, .wr_ready,
        .wr_data, .wr_keep, .wr_last,
        .full, .almost_full, .wr_core_used(wr_used),
        .rd_clk, .rd_rstn, .rd_valid, .rd_ready,
        .rd_data, .rd_keep, .rd_last,
        .empty, .almost_empty, .rd_core_used(rd_used)
    );

    stream_assertions #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) output_protocol (
        .clk(rd_clk),
        .rstn(rd_rstn),
        .valid(rd_valid),
        .ready(rd_ready),
        .data(rd_data),
        .keep(rd_keep),
        .last(rd_last)
    );

    always @(negedge wr_clk) begin
        if (!wr_rstn) begin
            wr_valid <= 1'b0;
        end
        else if (!producer_done) begin
            if (!wr_valid || wr_ready) begin
                if (generated == ITEM_COUNT) begin
                    wr_valid <= 1'b0;
                    producer_done <= 1'b1;
                end
                else if (($urandom(seed) % 100) < 78) begin
                    if (packet_remaining == 0)
                        packet_remaining = ($urandom(seed) % 6) + 1;

                    wr_data <= $urandom(seed);
                    wr_last <= (packet_remaining == 1);
                    if (packet_remaining == 1)
                        wr_keep <= (($urandom(seed) & 1) != 0) ?
                                   2'b11 : 2'b01;
                    else
                        wr_keep <= 2'b11;
                    wr_valid <= 1'b1;
                end
                else begin
                    wr_valid <= 1'b0;
                end
            end
        end
        else begin
            wr_valid <= 1'b0;
        end
    end

    always @(posedge wr_clk) begin
        if (wr_rstn && wr_valid && wr_ready) begin
            expected_data[push_index] = wr_data;
            expected_keep[push_index] = wr_keep;
            expected_last[push_index] = wr_last;
            push_index = push_index + 1;
            generated = generated + 1;
            packet_remaining = packet_remaining - 1;
        end
    end

    always @(negedge rd_clk) begin
        if (!rd_rstn)
            rd_ready <= 1'b0;
        else if (producer_done)
            rd_ready <= 1'b1;
        else
            rd_ready <= (($urandom(seed) % 100) < 57);
    end

    always @(posedge rd_clk) begin
        if (rd_rstn && rd_valid && rd_ready) begin
            assert (pop_index < push_index)
                else $fatal(1, "stream produced an unexpected item");
            assert ({rd_data, rd_keep, rd_last} ===
                    {expected_data[pop_index],
                     expected_keep[pop_index],
                     expected_last[pop_index]})
                else $fatal(1,
                    "stream scoreboard mismatch at %0d", pop_index);
            pop_index = pop_index + 1;
        end
    end

    initial begin
        #30;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        wait (producer_done);
        wait ((pop_index == ITEM_COUNT) && empty && !rd_valid);
        $display(
            "PASS: randomized stream scoreboard and backpressure (%0d beats)",
            pop_index
        );
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "random stream test timed out");
    end
endmodule

module tb_fifo_random;
    localparam DATA_WIDTH = 16;
    localparam ADDR_WIDTH = 4;
    localparam DEPTH = 1 << ADDR_WIDTH;
    localparam MAX_ITEMS = 8192;

    logic                  wr_clk = 1'b0;
    logic                  rd_clk = 1'b0;
    logic                  wr_rstn = 1'b0;
    logic                  rd_rstn = 1'b0;
    logic                  wr_en = 1'b0;
    logic                  rd_en = 1'b0;
    logic [DATA_WIDTH-1:0] wr_data = '0;
    wire  [DATA_WIDTH-1:0] rd_data;
    wire                   rd_valid;
    wire                   full;
    wire                   almost_full;
    wire                   empty;
    wire                   almost_empty;
    wire  [ADDR_WIDTH:0]   wr_used;
    wire  [ADDR_WIDTH:0]   rd_used;

    logic [DATA_WIDTH-1:0] expected_mem [0:MAX_ITEMS-1];
    integer push_index = 0;
    integer pop_index = 0;
    integer accepted_writes = 0;
    integer accepted_reads = 0;
    integer write_cycles = 0;
    integer seed = 32'h5eed1234;
    logic producer_done = 1'b0;

    // Unrelated prime-number clock periods exercise a changing phase relation.
    always #3.5 wr_clk = ~wr_clk;  // 7 ns
    always #5.5 rd_clk = ~rd_clk;  // 11 ns

    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ALMOST_FULL_THRESHOLD(DEPTH - 2),
        .ALMOST_EMPTY_THRESHOLD(2)
    ) dut (
        .wr_clk, .wr_rstn, .wr_en, .wr_data(wr_data),
        .full, .almost_full, .wr_used,
        .rd_clk, .rd_rstn, .rd_en, .rd_data(rd_data), .rd_valid,
        .empty, .almost_empty, .rd_used
    );

    fifo_assertions #(
        .PTR_WIDTH(ADDR_WIDTH + 1)
    ) assertions (
        .wr_clk,
        .wr_rstn,
        .wr_request(wr_en),
        .full,
        .wptr_gray(dut.u_async_fifo_core.wptr_gray),
        .rd_clk,
        .rd_rstn,
        .rd_request(rd_en),
        .empty,
        .rptr_gray(dut.u_async_fifo_core.rptr_gray)
    );

    always @(negedge wr_clk) begin
        if (!wr_rstn) begin
            wr_en <= 1'b0;
            wr_data   <= '0;
        end
        else if (!producer_done) begin
            wr_en <= (($urandom(seed) % 100) < 72);
            wr_data   <= $urandom(seed);
            write_cycles <= write_cycles + 1;
            if (write_cycles >= 2500)
                producer_done <= 1'b1;
        end
        else begin
            wr_en <= 1'b0;
        end
    end

    always @(negedge rd_clk) begin
        if (!rd_rstn)
            rd_en <= 1'b0;
        else if (producer_done)
            rd_en <= 1'b1;
        else
            rd_en <= (($urandom(seed) % 100) < 61);
    end

    always @(posedge wr_clk) begin
        if (wr_rstn) begin
            assert (wr_used <= DEPTH)
                else $fatal(1, "wr_used exceeded FIFO depth");
            if (wr_en && !full) begin
                assert (push_index < MAX_ITEMS)
                    else $fatal(1, "scoreboard storage exhausted");
                expected_mem[push_index] = wr_data;
                push_index = push_index + 1;
                accepted_writes = accepted_writes + 1;
            end
        end
    end

    always @(posedge rd_clk) begin
        #1;
        if (rd_rstn) begin
            assert (rd_used <= DEPTH)
                else $fatal(1, "rd_used exceeded FIFO depth");
            if (rd_valid) begin
                assert (pop_index < push_index)
                    else $fatal(1, "FIFO produced data absent from scoreboard");
                assert (rd_data === expected_mem[pop_index])
                    else $fatal(1,
                        "random scoreboard mismatch index=%0d expected=%h got=%h",
                        pop_index, expected_mem[pop_index], rd_data);
                pop_index = pop_index + 1;
                accepted_reads = accepted_reads + 1;
            end
        end
    end

    initial begin
        #30;
        wr_rstn = 1'b1;
        rd_rstn = 1'b1;

        wait (producer_done);
        wait ((pop_index == push_index) && empty && !rd_valid);
        repeat (4) @(posedge rd_clk);

        assert (accepted_writes > (DEPTH * 20))
            else $fatal(1, "random test did not generate enough traffic");
        assert (accepted_reads == accepted_writes)
            else $fatal(1, "random test ended with missing reads");

        $display(
            "PASS: randomized 7ns/11ns clocks and scoreboard (%0d transfers)",
            accepted_reads
        );
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "random FIFO test timed out");
    end
endmodule
