`timescale 1ns/1ps

// Equal-width first-word-fall-through wrapper.
//
// The Cummings-style async FIFO core remains a standard synchronous-read FIFO.
// This wrapper adds read-domain prefetch storage so the first readable word is
// placed on rd_data automatically and held stable until rd_en consumes it.
module async_fifo_fwft #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 9,
    parameter ALMOST_FULL_THRESHOLD = (1 << ADDR_WIDTH) - 1,
    parameter ALMOST_EMPTY_THRESHOLD = 1
) (
    input                   wr_clk,
    input                   wr_rstn,
    input                   wr_en,
    input  [DATA_WIDTH-1:0] wr_data,
    output                  full,
    output                  almost_full,
    output [ADDR_WIDTH:0]   wr_used,

    input                   rd_clk,
    input                   rd_rstn,
    input                   rd_en,
    output [DATA_WIDTH-1:0] rd_data,
    output                  rd_valid,
    output                  empty,
    output                  almost_empty,
    output [ADDR_WIDTH:0]   rd_used
);

    localparam PREFETCH_COUNT_WIDTH = 2;
    localparam [PREFETCH_COUNT_WIDTH-1:0] PREFETCH_DEPTH = 2;

    wire [DATA_WIDTH-1:0] core_rd_data;
    wire                  core_rd_valid;
    wire                  core_empty;
    wire                  unused_core_almost_empty;
    wire [ADDR_WIDTH:0]   core_rd_used;

    reg [DATA_WIDTH-1:0] slot0_data;
    reg [DATA_WIDTH-1:0] slot1_data;
    reg                  slot0_valid;
    reg                  slot1_valid;
    reg                  fetch_pending;

    wire                  pop;
    wire [PREFETCH_COUNT_WIDTH-1:0] slot_count;
    wire [PREFETCH_COUNT_WIDTH-1:0] reserved_count;
    wire [PREFETCH_COUNT_WIDTH-1:0] reserved_after_pop;
    wire                  core_rd_en;

    assign rd_data  = slot0_data;
    assign rd_valid = slot0_valid;
    assign empty    = !slot0_valid;

    // Keep the public occupancy view conservative and user-facing by adding
    // read-domain prefetch storage to the core read-domain estimate.
    assign rd_used =
        core_rd_used + {{ADDR_WIDTH{1'b0}}, slot0_valid} +
        {{ADDR_WIDTH{1'b0}}, slot1_valid} +
        {{ADDR_WIDTH{1'b0}}, fetch_pending};
    assign almost_empty = (rd_used <= ALMOST_EMPTY_THRESHOLD[ADDR_WIDTH:0]);

    assign pop = rd_rstn && rd_en && slot0_valid;
    assign slot_count =
        {1'b0, slot0_valid} + {1'b0, slot1_valid};
    assign reserved_count =
        slot_count + {1'b0, fetch_pending};
    assign reserved_after_pop =
        reserved_count - {1'b0, pop};

    // Fetch ahead until the two read-side slots are reserved. A pending core
    // read consumes one reservation until core_rd_valid returns the data.
    assign core_rd_en =
        rd_rstn && !core_empty &&
        (reserved_after_pop < PREFETCH_DEPTH);

    async_fifo_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ALMOST_FULL_THRESHOLD(ALMOST_FULL_THRESHOLD),
        .ALMOST_EMPTY_THRESHOLD(ALMOST_EMPTY_THRESHOLD)
    ) u_async_fifo_core (
        .wr_clk       (wr_clk),
        .wr_rstn      (wr_rstn),
        .wr_en        (wr_en),
        .wr_data      (wr_data),
        .full         (full),
        .almost_full  (almost_full),
        .wr_used      (wr_used),
        .rd_clk       (rd_clk),
        .rd_rstn      (rd_rstn),
        .rd_en        (core_rd_en),
        .rd_data      (core_rd_data),
        .rd_valid     (core_rd_valid),
        .empty        (core_empty),
        .almost_empty (unused_core_almost_empty),
        .rd_used      (core_rd_used)
    );

    always @(posedge rd_clk or negedge rd_rstn) begin
        if (!rd_rstn) begin
            slot0_data    <= {DATA_WIDTH{1'b0}};
            slot1_data    <= {DATA_WIDTH{1'b0}};
            slot0_valid   <= 1'b0;
            slot1_valid   <= 1'b0;
            fetch_pending <= 1'b0;
        end
        else begin
            case ({pop, core_rd_valid})
                2'b00: begin
                    slot0_valid <= slot0_valid;
                    slot1_valid <= slot1_valid;
                end
                2'b01: begin
                    if (!slot0_valid) begin
                        slot0_data  <= core_rd_data;
                        slot0_valid <= 1'b1;
                    end
                    else if (!slot1_valid) begin
                        slot1_data  <= core_rd_data;
                        slot1_valid <= 1'b1;
                    end
                end
                2'b10: begin
                    if (slot1_valid) begin
                        slot0_data  <= slot1_data;
                        slot0_valid <= 1'b1;
                        slot1_valid <= 1'b0;
                    end
                    else begin
                        slot0_valid <= 1'b0;
                    end
                end
                2'b11: begin
                    if (slot1_valid) begin
                        slot0_data  <= slot1_data;
                        slot1_data  <= core_rd_data;
                        slot0_valid <= 1'b1;
                        slot1_valid <= 1'b1;
                    end
                    else begin
                        slot0_data  <= core_rd_data;
                        slot0_valid <= 1'b1;
                        slot1_valid <= 1'b0;
                    end
                end
            endcase

            fetch_pending <= fetch_pending + core_rd_en - core_rd_valid;
        end
    end

    initial begin
        if (DATA_WIDTH < 1)
            $fatal(1, "DATA_WIDTH must be at least one");
        if (ADDR_WIDTH < 1)
            $fatal(1, "ADDR_WIDTH must be at least one");
    end

endmodule
