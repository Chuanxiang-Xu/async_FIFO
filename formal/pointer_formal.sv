`default_nettype none

module pointer_formal;
    localparam ADDR_WIDTH = 3;
    localparam PTR_WIDTH = ADDR_WIDTH + 1;

    (* gclk *) reg clk;
    reg rst_n = 1'b0;

    (* anyseq *) reg write_request;
    (* anyseq *) reg read_request;
    (* anyseq *) reg [PTR_WIDTH-1:0] synchronized_read_gray;
    (* anyseq *) reg [PTR_WIDTH-1:0] synchronized_write_gray;

    wire [ADDR_WIDTH-1:0] write_address;
    wire [PTR_WIDTH-1:0] write_gray;
    wire write_full;
    wire write_almost_full;
    wire [PTR_WIDTH-1:0] write_used;

    wire [ADDR_WIDTH-1:0] read_address;
    wire [PTR_WIDTH-1:0] read_gray;
    wire read_empty;
    wire read_almost_empty;
    wire [PTR_WIDTH-1:0] read_used;

    reg past_valid = 1'b0;

    always @(posedge clk) begin
        past_valid <= 1'b1;
        rst_n <= 1'b1;

        if (past_valid && $past(rst_n)) begin
            assert ((((write_gray ^ $past(write_gray)) &
                     ((write_gray ^ $past(write_gray)) - 1'b1))) == 0);
            assert ((((read_gray ^ $past(read_gray)) &
                     ((read_gray ^ $past(read_gray)) - 1'b1))) == 0);

            if ($past(write_request && write_full))
                assert (write_gray == $past(write_gray));
            if ($past(read_request && read_empty))
                assert (read_gray == $past(read_gray));
        end
    end

    wptr_full #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) write_pointer (
        .wclk(clk),
        .wrst_n(rst_n),
        .winc(write_request),
        .rptr_gray_sync(synchronized_read_gray),
        .waddr(write_address),
        .wptr_gray(write_gray),
        .wfull(write_full),
        .walmost_full(write_almost_full),
        .wused(write_used)
    );

    rptr_empty #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) read_pointer (
        .rclk(clk),
        .rrst_n(rst_n),
        .rinc(read_request),
        .wptr_gray_sync(synchronized_write_gray),
        .raddr(read_address),
        .rptr_gray(read_gray),
        .rempty(read_empty),
        .ralmost_empty(read_almost_empty),
        .rused(read_used)
    );

endmodule

`default_nettype wire
