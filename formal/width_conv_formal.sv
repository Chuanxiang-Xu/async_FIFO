`timescale 1ns/1ps
`default_nettype none

// End-to-end checks for both directions of the request-based width converter.
// Unique 8-bit slice tokens avoid the short-period aliasing of tiny counters.
// At the selected clock rates, fewer than 256 accepted slices are reachable
// inside the configured BMC depth.

module width_conv_pack_formal;
    localparam WDATA_WIDTH = 8;
    localparam RDATA_WIDTH = 16;
    localparam ADDR_WIDTH  = 3;
    localparam CORE_DEPTH  = 1 << (ADDR_WIDTH - 1);

    (* gclk *) reg global_clock;
    (* anyseq *) reg wr_en;
    (* anyseq *) reg rd_en;

    reg wr_clk = 1'b0;
    reg rd_clk = 1'b0;
    reg wr_div = 1'b0;
    reg [1:0] rd_div = 2'b00;
    reg [4:0] init_count = 0;

    always @(posedge global_clock) begin
        if (wr_div) begin
            wr_clk <= !wr_clk;
            wr_div <= 1'b0;
        end
        else begin
            wr_div <= 1'b1;
        end

        if (rd_div == 2) begin
            rd_clk <= !rd_clk;
            rd_div <= 0;
        end
        else begin
            rd_div <= rd_div + 1'b1;
        end

        if (init_count < 12)
            init_count <= init_count + 1'b1;
    end

    wire wr_rstn = (init_count >= 12);
    wire rd_rstn = (init_count >= 12);

    reg [WDATA_WIDTH-1:0] write_token = 0;
    reg [WDATA_WIDTH-1:0] expected_token = 0;

    wire [RDATA_WIDTH-1:0] rd_data;
    wire rd_valid;
    wire empty;
    wire full;
    wire almost_empty;
    wire almost_full;
    wire [ADDR_WIDTH:0] wr_core_used;
    wire [ADDR_WIDTH:0] rd_core_used;

    async_fifo_width_conv #(
        .WDATA_WIDTH(WDATA_WIDTH),
        .RDATA_WIDTH(RDATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk,
        .wr_rstn,
        .wr_en,
        .wr_data(write_token),
        .rd_clk,
        .rd_rstn,
        .rd_en,
        .rd_data,
        .rd_valid,
        .empty,
        .full,
        .almost_empty,
        .almost_full,
        .wr_core_used,
        .rd_core_used
    );

    always @(posedge wr_clk) begin
        if (!wr_rstn) begin
            write_token <= 0;
        end
        else begin
            if (wr_en && !full)
                write_token <= write_token + 1'b1;

            assert (wr_core_used <= CORE_DEPTH);
            cover (full);
        end
    end

    always @(posedge rd_clk) begin
        if (!rd_rstn) begin
            expected_token <= 0;
        end
        else begin
            assert (rd_core_used <= CORE_DEPTH);

            if (rd_valid) begin
                assert (rd_data == {
                    expected_token + 1'b1,
                    expected_token
                });
                expected_token <= expected_token + 2'd2;
            end

            cover (rd_valid && (expected_token >= 8));
        end
    end
endmodule


module width_conv_split_formal;
    localparam WDATA_WIDTH = 16;
    localparam RDATA_WIDTH = 8;
    localparam ADDR_WIDTH  = 3;
    localparam CORE_DEPTH  = 1 << (ADDR_WIDTH - 1);

    (* gclk *) reg global_clock;
    (* anyseq *) reg wr_en;
    (* anyseq *) reg rd_en;

    reg wr_clk = 1'b0;
    reg rd_clk = 1'b0;
    reg wr_div = 1'b0;
    reg [1:0] rd_div = 2'b00;
    reg [4:0] init_count = 0;

    always @(posedge global_clock) begin
        if (wr_div) begin
            wr_clk <= !wr_clk;
            wr_div <= 1'b0;
        end
        else begin
            wr_div <= 1'b1;
        end

        if (rd_div == 2) begin
            rd_clk <= !rd_clk;
            rd_div <= 0;
        end
        else begin
            rd_div <= rd_div + 1'b1;
        end

        if (init_count < 12)
            init_count <= init_count + 1'b1;
    end

    wire wr_rstn = (init_count >= 12);
    wire rd_rstn = (init_count >= 12);

    reg [RDATA_WIDTH-1:0] write_token = 0;
    reg [RDATA_WIDTH-1:0] expected_token = 0;
    wire [WDATA_WIDTH-1:0] wr_data = {
        write_token + 1'b1,
        write_token
    };

    wire [RDATA_WIDTH-1:0] rd_data;
    wire rd_valid;
    wire empty;
    wire full;
    wire almost_empty;
    wire almost_full;
    wire [ADDR_WIDTH:0] wr_core_used;
    wire [ADDR_WIDTH:0] rd_core_used;

    async_fifo_width_conv #(
        .WDATA_WIDTH(WDATA_WIDTH),
        .RDATA_WIDTH(RDATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk,
        .wr_rstn,
        .wr_en,
        .wr_data,
        .rd_clk,
        .rd_rstn,
        .rd_en,
        .rd_data,
        .rd_valid,
        .empty,
        .full,
        .almost_empty,
        .almost_full,
        .wr_core_used,
        .rd_core_used
    );

    always @(posedge wr_clk) begin
        if (!wr_rstn) begin
            write_token <= 0;
        end
        else begin
            if (wr_en && !full)
                write_token <= write_token + 2'd2;

            assert (wr_core_used <= CORE_DEPTH);
            cover (full);
        end
    end

    always @(posedge rd_clk) begin
        if (!rd_rstn) begin
            expected_token <= 0;
        end
        else begin
            assert (rd_core_used <= CORE_DEPTH);

            if (rd_valid) begin
                assert (rd_data == expected_token);
                expected_token <= expected_token + 1'b1;
            end

            cover (rd_valid && (expected_token >= 8));
        end
    end
endmodule

`default_nettype wire
