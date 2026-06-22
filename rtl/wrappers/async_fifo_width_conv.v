`timescale 1ns/1ps

// Optional wrapper around async_fifo_core for request-based width conversion.
// Use rtl/async_fifo.v when both interfaces have the same data width.
module async_fifo_width_conv #(
    parameter WDATA_WIDTH = 16,
    parameter RDATA_WIDTH = 32,
    // Core RAM capacity is 2**ADDR_WIDTH entries of the narrower interface.
    // Wrapper-local pack/pending/split storage can hold one additional
    // CORE_WIDTH word equivalent; see docs/interface.md for the contract.
    parameter ADDR_WIDTH  = 10,
    // Thresholds are measured in internal CORE_WIDTH words. A value of -1
    // selects the default: core depth minus one for almost_full, one for
    // almost_empty.
    parameter ALMOST_FULL_THRESHOLD  = -1,
    parameter ALMOST_EMPTY_THRESHOLD = -1
) (
    input                        wr_clk,
    input                        wr_rstn,
    input                        wr_en,
    input      [WDATA_WIDTH-1:0] wr_data,

    input                        rd_clk,
    input                        rd_rstn,
    input                        rd_en,
    output reg [RDATA_WIDTH-1:0] rd_data,
    output                       rd_valid,

    output                       empty,
    output                       full,
    output                       almost_empty,
    output                       almost_full,
    // Core-only local-domain occupancy views, zero-extended to
    // ADDR_WIDTH+1 bits. Local pack/pending/split buffers are not included.
    // Values are measured in internal CORE_WIDTH words.
    output     [ADDR_WIDTH:0]    wr_core_used,
    output     [ADDR_WIDTH:0]    rd_core_used
);

    // The asynchronous FIFO core is deliberately equal-width. Width
    // conversion is kept outside the CDC logic:
    //   narrow write -> wide read: pack in the write domain
    //   wide write   -> narrow read: split in the read domain
    //
    // ADDR_WIDTH describes core RAM capacity in narrower-interface units:
    // core narrow-entry equivalent = 2**ADDR_WIDTH. Wrapper-local storage is
    // intentionally excluded from this parameter and from *_core_used.
    localparam CORE_WIDTH = (WDATA_WIDTH > RDATA_WIDTH) ?
                            WDATA_WIDTH : RDATA_WIDTH;
    localparam UNIT_WIDTH = (WDATA_WIDTH < RDATA_WIDTH) ?
                            WDATA_WIDTH : RDATA_WIDTH;
    localparam SAFE_UNIT_WIDTH = (UNIT_WIDTH > 0) ? UNIT_WIDTH : 1;
    localparam WIDTH_RATIO_RAW = CORE_WIDTH / SAFE_UNIT_WIDTH;
    localparam WIDTH_RATIO = (WIDTH_RATIO_RAW > 0) ? WIDTH_RATIO_RAW : 1;
    localparam RATIO_SHIFT = (WIDTH_RATIO > 1) ? $clog2(WIDTH_RATIO) : 0;
    localparam CORE_ADDR_WIDTH_RAW = ADDR_WIDTH - RATIO_SHIFT;
    localparam CORE_ADDR_WIDTH =
        (CORE_ADDR_WIDTH_RAW > 0) ? CORE_ADDR_WIDTH_RAW : 1;
    localparam CORE_DEPTH = (1 << CORE_ADDR_WIDTH);
    localparam CORE_ALMOST_FULL_THRESHOLD =
        (ALMOST_FULL_THRESHOLD < 0) ?
        CORE_DEPTH - 1 : ALMOST_FULL_THRESHOLD;
    localparam CORE_ALMOST_EMPTY_THRESHOLD =
        (ALMOST_EMPTY_THRESHOLD < 0) ?
        1 : ALMOST_EMPTY_THRESHOLD;

    wire                  core_full;
    wire                  core_empty;
    wire                  core_rd_valid;
    wire                  core_almost_full;
    wire                  core_almost_empty;
    wire [CORE_ADDR_WIDTH:0] core_wr_used;
    wire [CORE_ADDR_WIDTH:0] core_rd_used;
    wire [CORE_WIDTH-1:0] core_rd_data;
    wire                  core_wr_en;
    wire                  core_rd_en;
    wire [CORE_WIDTH-1:0] core_wr_data;

    generate
        if (WDATA_WIDTH == RDATA_WIDTH) begin : g_equal_width
            assign full           = core_full;
            assign empty          = core_empty;
            assign core_wr_en   = wr_en;
            assign core_wr_data = wr_data;
            assign core_rd_en   = rd_en;
            assign rd_valid     = core_rd_valid;

            always @(*) begin
                rd_data = core_rd_data;
            end
        end
        else if (WDATA_WIDTH < RDATA_WIDTH) begin : g_pack_write
            localparam COUNT_WIDTH =
                (WIDTH_RATIO > 1) ? $clog2(WIDTH_RATIO) : 1;

            reg [CORE_WIDTH-1:0] pack_data;
            reg [COUNT_WIDTH-1:0] pack_count;
            reg [CORE_WIDTH-1:0] pending_data;
            reg                  pending_valid;
            wire accept_write;
            wire pack_complete;
            wire pending_accept;

            assign empty = core_empty;
            assign pack_complete =
                (pack_count == {COUNT_WIDTH{1'b1}});
            // One completed wide word can wait locally while the asynchronous
            // core is full. This lets a partially assembled word accept its
            // final narrow slice without first requiring the read side to
            // release core space.
            assign full = pending_valid;
            assign accept_write = wr_en && !full;
            assign pending_accept = pending_valid && !core_full;

            assign core_wr_en = pending_valid;
            // Little-slice-first packing:
            // for 16 -> 32, writes A then B produce {B, A}.
            assign core_wr_data = pending_data;
            assign core_rd_en = rd_en;
            assign rd_valid = core_rd_valid;

            always @(posedge wr_clk or negedge wr_rstn) begin
                if (!wr_rstn) begin
                    pack_data  <= {CORE_WIDTH{1'b0}};
                    pack_count <= {COUNT_WIDTH{1'b0}};
                    pending_data  <= {CORE_WIDTH{1'b0}};
                    pending_valid <= 1'b0;
                end
                else begin
                    if (pending_accept)
                        pending_valid <= 1'b0;

                    if (accept_write) begin
                        if (pack_complete) begin
                            pending_data <=
                                pack_data |
                                ({{(CORE_WIDTH-WDATA_WIDTH){1'b0}}, wr_data}
                                 << (pack_count * WDATA_WIDTH));
                            pending_valid <= 1'b1;
                            pack_data  <= {CORE_WIDTH{1'b0}};
                            pack_count <= {COUNT_WIDTH{1'b0}};
                        end
                        else begin
                            pack_data[
                                pack_count*WDATA_WIDTH +: WDATA_WIDTH
                            ] <= wr_data;
                            pack_count <= pack_count + 1'b1;
                        end
                    end
                end
            end

            always @(*) begin
                rd_data = core_rd_data;
            end
        end
        else begin : g_split_read
            localparam COUNT_WIDTH =
                (WIDTH_RATIO > 1) ? $clog2(WIDTH_RATIO) : 1;

            reg [CORE_WIDTH-1:0] split_data;
            reg [COUNT_WIDTH-1:0] split_count;
            reg                   split_valid;
            reg                   fetch_pending;
            reg                   split_rd_valid;

            assign full         = core_full;
            assign core_wr_en   = wr_en;
            assign core_wr_data = wr_data;
            // Fetch a new wide RAM word only after all buffered narrow slices
            // have been consumed. fetch_pending covers synchronous RAM latency.
            assign core_rd_en   = rd_en && !split_valid &&
                                  !fetch_pending && !core_empty;

            assign empty = !split_valid &&
                           (fetch_pending || core_empty);
            assign rd_valid = split_rd_valid;

            always @(posedge rd_clk or negedge rd_rstn) begin
                if (!rd_rstn) begin
                    rd_data       <= {RDATA_WIDTH{1'b0}};
                    split_data    <= {CORE_WIDTH{1'b0}};
                    split_count   <= {COUNT_WIDTH{1'b0}};
                    split_valid   <= 1'b0;
                    fetch_pending <= 1'b0;
                    split_rd_valid <= 1'b0;
                end
                else begin
                    split_rd_valid <= 1'b0;

                    if (core_rd_en)
                        fetch_pending <= 1'b1;

                    if (core_rd_valid) begin
                        // Little-slice-first splitting:
                        // 32'h1122_3344 is read as 16'h3344, then 16'h1122.
                        rd_data       <= core_rd_data[RDATA_WIDTH-1:0];
                        split_data    <= core_rd_data;
                        split_count   <= {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
                        split_valid   <= (WIDTH_RATIO > 1);
                        fetch_pending <= 1'b0;
                        split_rd_valid <= 1'b1;
                    end
                    else if (rd_en && split_valid) begin
                        rd_data <= split_data[
                            split_count*RDATA_WIDTH +: RDATA_WIDTH
                        ];
                        split_rd_valid <= 1'b1;

                        if (split_count == {COUNT_WIDTH{1'b1}}) begin
                            split_count <= {COUNT_WIDTH{1'b0}};
                            split_valid <= 1'b0;
                        end
                        else begin
                            split_count <= split_count + 1'b1;
                        end
                    end
                end
            end
        end
    endgenerate

    // These advisory flags report occupancy in internal CORE_WIDTH words.
    // In split-read mode, slices already buffered outside the core are not
    // included in almost_empty.
    assign almost_full  = core_almost_full;
    assign almost_empty = core_almost_empty;
    assign wr_core_used = {{RATIO_SHIFT{1'b0}}, core_wr_used};
    assign rd_core_used = {{RATIO_SHIFT{1'b0}}, core_rd_used};

    async_fifo_core #(
        .DATA_WIDTH(CORE_WIDTH),
        .ADDR_WIDTH(CORE_ADDR_WIDTH),
        .ALMOST_FULL_THRESHOLD(CORE_ALMOST_FULL_THRESHOLD),
        .ALMOST_EMPTY_THRESHOLD(CORE_ALMOST_EMPTY_THRESHOLD)
    ) u_async_fifo_core (
        .wr_clk   (wr_clk),
        .wr_rstn  (wr_rstn),
        .wr_en    (core_wr_en),
        .wr_data  (core_wr_data),
        .full     (core_full),
        .almost_full(core_almost_full),
        .wr_used  (core_wr_used),
        .rd_clk   (rd_clk),
        .rd_rstn  (rd_rstn),
        .rd_en    (core_rd_en),
        .rd_data  (core_rd_data),
        .rd_valid (core_rd_valid),
        .empty    (core_empty),
        .almost_empty(core_almost_empty),
        .rd_used  (core_rd_used)
    );

    // This implementation intentionally uses the conventional power-of-two
    // reflected-Gray pointer scheme. Unsupported parameter combinations fail
    // early in simulation instead of silently producing unsafe CDC behavior.
    initial begin
        if ((WDATA_WIDTH < 1) || (RDATA_WIDTH < 1))
            $fatal(1, "WDATA_WIDTH and RDATA_WIDTH must be positive");
        if ((CORE_WIDTH % SAFE_UNIT_WIDTH) != 0)
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
