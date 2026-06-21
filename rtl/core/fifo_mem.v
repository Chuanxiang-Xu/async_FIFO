`timescale 1ns/1ps

module fifo_mem #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 9
) (
    input                       wclk,
    input                       wclken,
    input      [ADDR_WIDTH-1:0] waddr,
    input      [DATA_WIDTH-1:0] wdata,

    input                       rclk,
    input                       rclken,
    input      [ADDR_WIDTH-1:0] raddr,
    output reg [DATA_WIDTH-1:0] rdata
);

    localparam DEPTH = (1 << ADDR_WIDTH);

    // Standard simple dual-port RAM inference template:
    //   port A: synchronous write in the write clock domain
    //   port B: synchronous read in the read clock domain
    // No reset is applied to the memory array, which improves block-RAM
    // inference. Pointer reset and empty/full flags protect invalid contents.
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge wclk) begin
        if (wclken)
            mem[waddr] <= wdata;
    end

    always @(posedge rclk) begin
        if (rclken)
            rdata <= mem[raddr];
    end

endmodule
