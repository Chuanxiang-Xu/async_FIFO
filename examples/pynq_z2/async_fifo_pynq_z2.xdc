# PYNQ-Z2 board pins and FIFO CDC constraints.
# Target part: xc7z020clg400-1

# External 125 MHz PL clock from the PYNQ-Z2 clock input.
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports sysclk]
create_clock -name sysclk -period 8.000 -waveform {0.000 4.000} [get_ports sysclk]

# Push button 0 is the active-high board reset request.
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports btn0]

# Four user LEDs.
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

# Name the MMCM-generated clocks at their BUFG outputs. Vivado also derives
# these clocks from the MMCM; the explicit names make the CDC constraints and
# reports deterministic for this example hierarchy.
create_generated_clock -name wr_clk \
    -source [get_ports sysclk] -multiply_by 4 -divide_by 5 \
    [get_pins u_wr_clk_bufg/O]
create_generated_clock -name rd_clk \
    -source [get_ports sysclk] -multiply_by 3 -divide_by 5 \
    [get_pins u_rd_clk_bufg/O]

# The external button and MMCM lock signal feed asynchronous reset assertion;
# reset release is synchronized independently in each generated clock domain.
set_false_path -from [get_ports btn0]

# Preserve both stages of the Gray-pointer synchronizers.
set_property ASYNC_REG TRUE [get_cells -hier -regexp \
    {.*u_sync_(w2r|r2w)/.*(gray_meta|gray_sync_reg).*}]

# Constrain each Gray crossing with its source-clock period. Do not add a broad
# set_clock_groups -asynchronous exception: it can override these max-delay
# constraints.
set wr_period [get_property PERIOD [get_clocks wr_clk]]
set rd_period [get_property PERIOD [get_clocks rd_clk]]

set wptr_meta_pins [get_pins -hier -regexp \
    {.*u_sync_w2r/.*wptr_gray_meta_reg.*/D}]
set rptr_meta_pins [get_pins -hier -regexp \
    {.*u_sync_r2w/.*rptr_gray_meta_reg.*/D}]

# Discover the actual sequential startpoints feeding the first synchronizer
# stage. Vivado can merge the Gray MSB with the identical binary-pointer MSB,
# so matching only cells named *ptr_gray_reg can silently omit one bus bit.
set wptr_source_regs [all_fanin -flat -startpoints_only -only_cells \
    -to $wptr_meta_pins]
set rptr_source_regs [all_fanin -flat -startpoints_only -only_cells \
    -to $rptr_meta_pins]

set_max_delay -datapath_only $wr_period \
    -from $wptr_source_regs -to $wptr_meta_pins
set_bus_skew $wr_period \
    -from $wptr_source_regs -to $wptr_meta_pins

set_max_delay -datapath_only $rd_period \
    -from $rptr_source_regs -to $rptr_meta_pins
set_bus_skew $rd_period \
    -from $rptr_source_regs -to $rptr_meta_pins
