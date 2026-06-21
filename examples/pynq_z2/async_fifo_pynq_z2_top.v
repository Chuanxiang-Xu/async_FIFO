`timescale 1ns/1ps

// PYNQ-Z2 implementation and hardware smoke-test top level.
//
// The board's 125 MHz PL clock feeds one MMCM, which produces a 100 MHz FIFO
// write clock and a 75 MHz FIFO read clock. A counter is written continuously;
// the read domain checks that every returned word is in sequence.
module async_fifo_pynq_z2_top (
    input        sysclk,
    input        btn0,
    output [3:0] led
);

    wire wr_clk_mmcm;
    wire rd_clk_mmcm;
    wire clk_feedback;
    wire clk_feedback_buf;
    wire wr_clk;
    wire rd_clk;
    wire mmcm_locked;

    // 125 MHz input, 750 MHz VCO:
    //   CLKOUT0 = 750 / 7.5 = 100 MHz
    //   CLKOUT1 = 750 / 10  =  75 MHz
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(8.000),
        .CLKFBOUT_MULT_F(6.000),
        .DIVCLK_DIVIDE(1),
        .CLKOUT0_DIVIDE_F(7.500),
        .CLKOUT1_DIVIDE(10),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1   (sysclk),
        .CLKFBIN  (clk_feedback_buf),
        .RST      (btn0),
        .PWRDWN   (1'b0),
        .CLKFBOUT (clk_feedback),
        .CLKOUT0  (wr_clk_mmcm),
        .CLKOUT1  (rd_clk_mmcm),
        .LOCKED   (mmcm_locked)
    );

    BUFG u_feedback_bufg (
        .I(clk_feedback),
        .O(clk_feedback_buf)
    );

    BUFG u_wr_clk_bufg (
        .I(wr_clk_mmcm),
        .O(wr_clk)
    );

    BUFG u_rd_clk_bufg (
        .I(rd_clk_mmcm),
        .O(rd_clk)
    );

    // BTN0 already resets the MMCM. Its LOCKED output consequently provides
    // the single asynchronous reset source for both local release chains.
    // Avoiding a multi-input LUT on asynchronous clear removes a potential
    // reset-glitch path reported by Vivado methodology checks.
    wire async_reset_n = mmcm_locked;
    wire wr_rstn;
    wire rd_rstn;

    async_reset_sync u_wr_reset_sync (
        .clk        (wr_clk),
        .async_rstn (async_reset_n),
        .sync_rstn  (wr_rstn)
    );

    async_reset_sync u_rd_reset_sync (
        .clk        (rd_clk),
        .async_rstn (async_reset_n),
        .sync_rstn  (rd_rstn)
    );

    reg  [31:0] wr_counter;
    reg  [31:0] rd_expected;
    reg         data_error;
    wire [31:0] rd_data;
    wire        rd_valid;
    wire        full;
    wire        empty;
    wire        almost_full;
    wire        almost_empty;
    wire [9:0]  wr_used;
    wire [9:0]  rd_used;

    wire wr_en = wr_rstn && !full;
    wire rd_en = rd_rstn && !empty;

    always @(posedge wr_clk or negedge wr_rstn) begin
        if (!wr_rstn)
            wr_counter <= 32'b0;
        else if (wr_en)
            wr_counter <= wr_counter + 1'b1;
    end

    always @(posedge rd_clk or negedge rd_rstn) begin
        if (!rd_rstn) begin
            rd_expected <= 32'b0;
            data_error  <= 1'b0;
        end
        else if (rd_valid) begin
            if (rd_data != rd_expected)
                data_error <= 1'b1;
            rd_expected <= rd_expected + 1'b1;
        end
    end

    async_fifo #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(9),
        .ALMOST_FULL_THRESHOLD(508),
        .ALMOST_EMPTY_THRESHOLD(4)
    ) u_async_fifo (
        .wr_clk      (wr_clk),
        .wr_rstn     (wr_rstn),
        .wr_en       (wr_en),
        .wr_data     (wr_counter),
        .full        (full),
        .almost_full (almost_full),
        .wr_used     (wr_used),
        .rd_clk      (rd_clk),
        .rd_rstn     (rd_rstn),
        .rd_en       (rd_en),
        .rd_data     (rd_data),
        .rd_valid    (rd_valid),
        .empty       (empty),
        .almost_empty(almost_empty),
        .rd_used     (rd_used)
    );

    // LED0: sticky data mismatch (must remain off)
    // LED1: FIFO full
    // LED2: successful-read heartbeat (about 2.2 Hz)
    // LED3: MMCM locked
    // Unlike an idle error LED, the heartbeat positively demonstrates that
    // the read clock, FIFO data path, and scoreboard are making progress.
    assign led = {mmcm_locked, rd_expected[24], full, data_error};

endmodule
