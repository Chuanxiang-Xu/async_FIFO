`timescale 1ns/1ps

// Packet-aware, width-converting asynchronous FIFO.
//
// Transfers use ready/valid handshakes in each clock domain. Byte-valid and
// packet-boundary metadata cross the FIFO together with the payload.
module async_fifo_stream #(
    parameter WDATA_WIDTH = 16,
    parameter RDATA_WIDTH = 32,
    // Core RAM capacity is 2**ADDR_WIDTH entries of the narrower interface.
    // The elastic write slot and two read-side slots add pipeline storage;
    // see docs/interface.md for the exact capacity contract.
    parameter ADDR_WIDTH  = 10,
    // Thresholds are measured in internal CORE_DATA_WIDTH words. A value of
    // -1 selects the default.
    parameter ALMOST_FULL_THRESHOLD  = -1,
    parameter ALMOST_EMPTY_THRESHOLD = -1
) (
    input                            wr_clk,
    input                            wr_rstn,
    input                            wr_valid,
    output                           wr_ready,
    input      [WDATA_WIDTH-1:0]     wr_data,
    input      [((WDATA_WIDTH+7)/8)-1:0] wr_keep,
    input                            wr_last,
    output                           full,
    output                           almost_full,
    // Core-only occupancy; local pack and pending buffers are not included.
    output     [ADDR_WIDTH:0]        wr_core_used,

    input                            rd_clk,
    input                            rd_rstn,
    output                           rd_valid,
    input                            rd_ready,
    output     [RDATA_WIDTH-1:0]     rd_data,
    output     [((RDATA_WIDTH+7)/8)-1:0] rd_keep,
    output                           rd_last,
    output                           empty,
    output                           almost_empty,
    // Core-only occupancy; both local output slots are excluded.
    output     [ADDR_WIDTH:0]        rd_core_used
);

    localparam CORE_DATA_WIDTH =
        (WDATA_WIDTH > RDATA_WIDTH) ? WDATA_WIDTH : RDATA_WIDTH;
    localparam WKEEP_WIDTH = (WDATA_WIDTH + 7) / 8;
    localparam RKEEP_WIDTH = (RDATA_WIDTH + 7) / 8;
    localparam CORE_KEEP_WIDTH = (CORE_DATA_WIDTH + 7) / 8;
    localparam UNIT_WIDTH =
        (WDATA_WIDTH < RDATA_WIDTH) ? WDATA_WIDTH : RDATA_WIDTH;
    localparam SAFE_UNIT_WIDTH = (UNIT_WIDTH > 0) ? UNIT_WIDTH : 1;
    localparam WIDTH_RATIO_RAW = CORE_DATA_WIDTH / SAFE_UNIT_WIDTH;
    localparam WIDTH_RATIO = (WIDTH_RATIO_RAW > 0) ? WIDTH_RATIO_RAW : 1;
    localparam RATIO_SHIFT = (WIDTH_RATIO > 1) ? $clog2(WIDTH_RATIO) : 0;
    localparam CORE_ADDR_WIDTH_RAW = ADDR_WIDTH - RATIO_SHIFT;
    localparam CORE_ADDR_WIDTH =
        (CORE_ADDR_WIDTH_RAW > 0) ? CORE_ADDR_WIDTH_RAW : 1;
    localparam CORE_DEPTH = (1 << CORE_ADDR_WIDTH);
    localparam CORE_PAYLOAD_WIDTH =
        CORE_DATA_WIDTH + CORE_KEEP_WIDTH + 1;
    localparam WRITE_RATIO = CORE_DATA_WIDTH / WDATA_WIDTH;
    localparam READ_RATIO  = CORE_DATA_WIDTH / RDATA_WIDTH;
    localparam WRITE_COUNT_WIDTH =
        (WRITE_RATIO > 1) ? $clog2(WRITE_RATIO) : 1;
    localparam READ_COUNT_WIDTH =
        (READ_RATIO > 1) ? $clog2(READ_RATIO) : 1;
    localparam CORE_ALMOST_FULL_THRESHOLD =
        (ALMOST_FULL_THRESHOLD < 0) ?
        CORE_DEPTH - 1 : ALMOST_FULL_THRESHOLD;
    localparam CORE_ALMOST_EMPTY_THRESHOLD =
        (ALMOST_EMPTY_THRESHOLD < 0) ?
        1 : ALMOST_EMPTY_THRESHOLD;

    wire                          core_full;
    wire                          core_empty;
    wire                          core_almost_full;
    wire                          core_almost_empty;
    wire                          core_rd_valid;
    wire [CORE_ADDR_WIDTH:0]      core_wr_used;
    wire [CORE_ADDR_WIDTH:0]      core_rd_used;
    wire [CORE_PAYLOAD_WIDTH-1:0] core_rd_payload;
    wire                          core_wr_en;
    wire                          core_rd_en;
    wire [CORE_PAYLOAD_WIDTH-1:0] core_wr_payload;

    reg [CORE_PAYLOAD_WIDTH-1:0] pending_payload;
    reg                          pending_valid;
    wire                         pending_pop;
    wire                         input_accept;

    assign core_wr_en      = pending_valid;
    assign core_wr_payload = pending_payload;
    assign pending_pop     = pending_valid && !core_full;
    assign input_accept    = wr_valid && wr_ready;
    assign full            = !wr_ready;
    assign almost_full     = core_almost_full;
    assign wr_core_used = {{RATIO_SHIFT{1'b0}}, core_wr_used};

    generate
        if (WRITE_RATIO == 1) begin : g_write_direct
            // A valid pending word may leave for the core on this edge while
            // a new input word replaces it. This one-entry elastic-buffer
            // behavior removes the former mandatory bubble between writes.
            assign wr_ready = !pending_valid || !core_full;

            always @(posedge wr_clk or negedge wr_rstn) begin
                if (!wr_rstn) begin
                    pending_payload <= {CORE_PAYLOAD_WIDTH{1'b0}};
                    pending_valid   <= 1'b0;
                end
                else begin
                    if (input_accept) begin
                        pending_payload <= {wr_last, wr_keep, wr_data};
                        pending_valid   <= 1'b1;
                    end
                    else if (pending_pop) begin
                        pending_valid <= 1'b0;
                    end
                end
            end
        end
        else begin : g_write_pack
            reg [CORE_DATA_WIDTH-1:0] pack_data;
            reg [CORE_KEEP_WIDTH-1:0] pack_keep;
            reg [WRITE_COUNT_WIDTH-1:0] pack_count;
            wire pack_complete;

            // Narrow slices may continue entering the pack register while an
            // older completed word leaves pending_payload. If the new slice
            // completes a word on the same edge, it replaces the departing
            // pending word without a bubble.
            assign wr_ready = !pending_valid || !core_full;
            assign pack_complete =
                (pack_count == {WRITE_COUNT_WIDTH{1'b1}});

            always @(posedge wr_clk or negedge wr_rstn) begin
                if (!wr_rstn) begin
                    pack_data       <= {CORE_DATA_WIDTH{1'b0}};
                    pack_keep       <= {CORE_KEEP_WIDTH{1'b0}};
                    pack_count      <= {WRITE_COUNT_WIDTH{1'b0}};
                    pending_payload <= {CORE_PAYLOAD_WIDTH{1'b0}};
                    pending_valid   <= 1'b0;
                end
                else begin
                    if (input_accept) begin
                        if (wr_last || pack_complete) begin
                            pending_payload <= {
                                wr_last,
                                pack_keep |
                                    ({{(CORE_KEEP_WIDTH-WKEEP_WIDTH){1'b0}},
                                      wr_keep}
                                     << (pack_count * WKEEP_WIDTH)),
                                pack_data |
                                    ({{(CORE_DATA_WIDTH-WDATA_WIDTH){1'b0}},
                                      wr_data}
                                     << (pack_count * WDATA_WIDTH))
                            };
                            pending_valid <= 1'b1;
                            pack_data  <= {CORE_DATA_WIDTH{1'b0}};
                            pack_keep  <= {CORE_KEEP_WIDTH{1'b0}};
                            pack_count <= {WRITE_COUNT_WIDTH{1'b0}};
                        end
                        else begin
                            pack_data[
                                pack_count*WDATA_WIDTH +: WDATA_WIDTH
                            ] <= wr_data;
                            pack_keep[
                                pack_count*WKEEP_WIDTH +: WKEEP_WIDTH
                            ] <= wr_keep;
                            pack_count <= pack_count + 1'b1;
                        end
                    end

                    if (pending_pop &&
                        !(input_accept && (wr_last || pack_complete)))
                        pending_valid <= 1'b0;
                end
            end
        end
    endgenerate

    reg [CORE_DATA_WIDTH-1:0] out_data;
    reg [CORE_KEEP_WIDTH-1:0] out_keep;
    reg                       out_last;
    reg [READ_COUNT_WIDTH-1:0] out_count;
    reg                       out_valid;
    reg [CORE_DATA_WIDTH-1:0] next_data;
    reg [CORE_KEEP_WIDTH-1:0] next_keep;
    reg                       next_last;
    reg                       next_valid;
    reg                       fetch_pending;
    wire                      current_last;
    wire                      final_slice;
    wire                      output_accept;
    wire                      output_final_accept;
    wire                      fetch_room;

    assign rd_valid = out_valid;

    generate
        if (READ_RATIO == 1) begin : g_read_direct_select
            // Avoid an unnecessary dynamic part-select. Besides producing
            // simpler hardware, this prevents an arbitrary pre-reset
            // out_count value from selecting beyond the payload width.
            assign rd_data = out_data[RDATA_WIDTH-1:0];
            assign rd_keep = out_keep[RKEEP_WIDTH-1:0];
        end
        else begin : g_read_slice_select
            assign rd_data =
                out_data[out_count*RDATA_WIDTH +: RDATA_WIDTH];
            assign rd_keep =
                out_keep[out_count*RKEEP_WIDTH +: RKEEP_WIDTH];
        end
    endgenerate

    assign final_slice =
        (out_count == {READ_COUNT_WIDTH{1'b1}}) ||
        !has_keep_after(out_keep, out_count);
    assign current_last = out_last && final_slice;
    assign rd_last = rd_valid && current_last;
    assign output_accept = rd_valid && rd_ready;
    assign output_final_accept = output_accept && final_slice;

    // Two local payload slots decouple synchronous RAM latency from the
    // output stream. A returning core word may fill/promote the current slot
    // while another read is launched on the same edge. The response-aware
    // room check reserves space for every outstanding read.
    assign fetch_room = core_rd_valid ?
        (!out_valid || (output_final_accept && !next_valid)) :
        (!out_valid || !next_valid || output_final_accept);
    assign core_rd_en = !core_empty &&
                        (!fetch_pending || core_rd_valid) && fetch_room;

    assign empty = !out_valid && !next_valid &&
                   (fetch_pending || core_empty);
    assign almost_empty = core_almost_empty;
    assign rd_core_used = {{RATIO_SHIFT{1'b0}}, core_rd_used};

    function has_keep_after;
        input [CORE_KEEP_WIDTH-1:0] keep_value;
        input [READ_COUNT_WIDTH-1:0] slice_index;
        integer i;
        integer next_slice_start;
        begin
            has_keep_after = 1'b0;
            next_slice_start =
                ({{(32-READ_COUNT_WIDTH){1'b0}}, slice_index} + 1) *
                RKEEP_WIDTH;
            for (i = 0; i < CORE_KEEP_WIDTH; i = i + 1)
                if ((i >= next_slice_start) &&
                    keep_value[i])
                    has_keep_after = 1'b1;
        end
    endfunction

    always @(posedge rd_clk or negedge rd_rstn) begin
        if (!rd_rstn) begin
            out_data      <= {CORE_DATA_WIDTH{1'b0}};
            out_keep      <= {CORE_KEEP_WIDTH{1'b0}};
            out_last      <= 1'b0;
            out_count     <= {READ_COUNT_WIDTH{1'b0}};
            out_valid     <= 1'b0;
            next_data     <= {CORE_DATA_WIDTH{1'b0}};
            next_keep     <= {CORE_KEEP_WIDTH{1'b0}};
            next_last     <= 1'b0;
            next_valid    <= 1'b0;
            fetch_pending <= 1'b0;
        end
        else begin
            // Consume the old response reservation and optionally create a
            // new one on the same edge for back-to-back core reads.
            if (core_rd_valid) begin
                fetch_pending <= core_rd_en;
            end
            else if (core_rd_en) begin
                fetch_pending <= 1'b1;
            end

            if (core_rd_valid) begin
                if (!out_valid) begin
                    out_data <= core_rd_payload[CORE_DATA_WIDTH-1:0];
                    out_keep <= core_rd_payload[
                        CORE_DATA_WIDTH +: CORE_KEEP_WIDTH
                    ];
                    out_last <= core_rd_payload[CORE_PAYLOAD_WIDTH-1];
                    out_count <= {READ_COUNT_WIDTH{1'b0}};
                    out_valid <= 1'b1;
                end
                else if (output_final_accept) begin
                    if (next_valid) begin
                        // Promote the prefetched word and refill the free
                        // next slot with the response arriving this edge.
                        out_data  <= next_data;
                        out_keep  <= next_keep;
                        out_last  <= next_last;
                        out_count <= {READ_COUNT_WIDTH{1'b0}};
                        out_valid <= 1'b1;

                        next_data <=
                            core_rd_payload[CORE_DATA_WIDTH-1:0];
                        next_keep <= core_rd_payload[
                            CORE_DATA_WIDTH +: CORE_KEEP_WIDTH
                        ];
                        next_last <=
                            core_rd_payload[CORE_PAYLOAD_WIDTH-1];
                        next_valid <= 1'b1;
                    end
                    else begin
                        // The response directly replaces the word consumed
                        // on this edge, avoiding an output bubble.
                        out_data <=
                            core_rd_payload[CORE_DATA_WIDTH-1:0];
                        out_keep <= core_rd_payload[
                            CORE_DATA_WIDTH +: CORE_KEEP_WIDTH
                        ];
                        out_last <=
                            core_rd_payload[CORE_PAYLOAD_WIDTH-1];
                        out_count <= {READ_COUNT_WIDTH{1'b0}};
                        out_valid <= 1'b1;
                    end
                end
                else begin
                    // The current word remains active; hold the returned
                    // payload in the prefetch slot.
                    next_data <= core_rd_payload[CORE_DATA_WIDTH-1:0];
                    next_keep <= core_rd_payload[
                        CORE_DATA_WIDTH +: CORE_KEEP_WIDTH
                    ];
                    next_last <= core_rd_payload[CORE_PAYLOAD_WIDTH-1];
                    next_valid <= 1'b1;

                    if (output_accept)
                        out_count <= out_count + 1'b1;
                end
            end
            else if (output_accept) begin
                if (final_slice) begin
                    if (next_valid) begin
                        out_data  <= next_data;
                        out_keep  <= next_keep;
                        out_last  <= next_last;
                        out_count <= {READ_COUNT_WIDTH{1'b0}};
                        out_valid <= 1'b1;
                        next_valid <= 1'b0;
                    end
                    else begin
                        out_count <= {READ_COUNT_WIDTH{1'b0}};
                        out_valid <= 1'b0;
                    end
                end
                else begin
                    out_count <= out_count + 1'b1;
                end
            end
        end
    end

    async_fifo_core #(
        .DATA_WIDTH(CORE_PAYLOAD_WIDTH),
        .ADDR_WIDTH(CORE_ADDR_WIDTH),
        .ALMOST_FULL_THRESHOLD(CORE_ALMOST_FULL_THRESHOLD),
        .ALMOST_EMPTY_THRESHOLD(CORE_ALMOST_EMPTY_THRESHOLD)
    ) u_async_fifo_core (
        .wr_clk      (wr_clk),
        .wr_rstn     (wr_rstn),
        .wr_en       (core_wr_en),
        .wr_data     (core_wr_payload),
        .full        (core_full),
        .almost_full (core_almost_full),
        .wr_used     (core_wr_used),
        .rd_clk      (rd_clk),
        .rd_rstn     (rd_rstn),
        .rd_en       (core_rd_en),
        .rd_data     (core_rd_payload),
        .rd_valid    (core_rd_valid),
        .empty       (core_empty),
        .almost_empty(core_almost_empty),
        .rd_used     (core_rd_used)
    );

    initial begin
        if ((WDATA_WIDTH < 8) || ((WDATA_WIDTH % 8) != 0))
            $fatal(1, "WDATA_WIDTH must be a positive multiple of eight");
        if ((RDATA_WIDTH < 8) || ((RDATA_WIDTH % 8) != 0))
            $fatal(1, "RDATA_WIDTH must be a positive multiple of eight");
        if ((CORE_DATA_WIDTH % SAFE_UNIT_WIDTH) != 0)
            $fatal(1, "WDATA_WIDTH and RDATA_WIDTH must have an integer ratio");
        if ((WIDTH_RATIO & (WIDTH_RATIO - 1)) != 0)
            $fatal(1, "Width ratio must be a power of two");
        if (CORE_ADDR_WIDTH_RAW < 1)
            $fatal(1, "ADDR_WIDTH is too small for the selected width ratio");
        if ((CORE_ALMOST_FULL_THRESHOLD < 0) ||
            (CORE_ALMOST_FULL_THRESHOLD > CORE_DEPTH))
            $fatal(1, "ALMOST_FULL_THRESHOLD must be between zero and core depth");
        if ((CORE_ALMOST_EMPTY_THRESHOLD < 0) ||
            (CORE_ALMOST_EMPTY_THRESHOLD > CORE_DEPTH))
            $fatal(1, "ALMOST_EMPTY_THRESHOLD must be between zero and core depth");
    end

endmodule
