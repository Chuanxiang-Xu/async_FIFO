`timescale 1ns/1ps

// Simulation assertions for the equal-width asynchronous FIFO core.
module fifo_assertions #(
    parameter PTR_WIDTH = 4
) (
    input                       wr_clk,
    input                       wr_rstn,
    input                       wr_request,
    input                       full,
    input      [PTR_WIDTH-1:0]  wptr_gray,
    input                       rd_clk,
    input                       rd_rstn,
    input                       rd_request,
    input                       empty,
    input      [PTR_WIDTH-1:0]  rptr_gray
);

    logic [PTR_WIDTH-1:0] previous_wptr;
    logic [PTR_WIDTH-1:0] previous_rptr;
    logic                 previous_blocked_write;
    logic                 previous_blocked_read;
    logic                 write_history_valid;
    logic                 read_history_valid;

    function automatic bit onehot0(input logic [PTR_WIDTH-1:0] value);
        begin
            onehot0 = ((value & (value - 1'b1)) == '0);
        end
    endfunction

    always @(posedge wr_clk or negedge wr_rstn) begin
        if (!wr_rstn) begin
            previous_wptr          <= '0;
            previous_blocked_write <= 1'b0;
            write_history_valid    <= 1'b0;
        end
        else begin
            if (write_history_valid) begin
                assert (onehot0(wptr_gray ^ previous_wptr))
                    else $fatal(1, "write Gray pointer changed by multiple bits");
                if (previous_blocked_write)
                    assert (wptr_gray == previous_wptr)
                        else $fatal(1, "write pointer moved while full");
            end
            previous_wptr          <= wptr_gray;
            previous_blocked_write <= full && wr_request;
            write_history_valid    <= 1'b1;
        end
    end

    always @(posedge rd_clk or negedge rd_rstn) begin
        if (!rd_rstn) begin
            previous_rptr         <= '0;
            previous_blocked_read <= 1'b0;
            read_history_valid    <= 1'b0;
        end
        else begin
            if (read_history_valid) begin
                assert (onehot0(rptr_gray ^ previous_rptr))
                    else $fatal(1, "read Gray pointer changed by multiple bits");
                if (previous_blocked_read)
                    assert (rptr_gray == previous_rptr)
                        else $fatal(1, "read pointer moved while empty");
            end
            previous_rptr         <= rptr_gray;
            previous_blocked_read <= empty && rd_request;
            read_history_valid    <= 1'b1;
        end
    end

endmodule
