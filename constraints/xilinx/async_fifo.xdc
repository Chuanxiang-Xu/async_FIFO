# Xilinx Vivado constraint template for this repository.
# Review all get_* matches against the synthesized design before use.

# Replace periods and port names with top-level project values.
create_clock -name wr_clk -period 10.000 [get_ports wr_clk]
create_clock -name rd_clk -period 14.000 [get_ports rd_clk]

# Set this to the exact synthesized hierarchy of one async_fifo_core instance.
# Do not use wildcards. Examples:
#   async_fifo top level:       u_async_fifo_core
#   PYNQ example wrapper:       u_async_fifo/u_async_fifo_core
#   stream/width-conv wrapper:  u_async_fifo_core
set fifo_instance {u_async_fifo_core}

# Replace this with ADDR_WIDTH + 1 for that async_fifo_core instance.
set fifo_pointer_width 10

# Preserve and identify both stages of each synchronizer chain.
set fifo_sync_regs [get_cells -quiet -hier -filter \
    "NAME =~ ${fifo_instance}/u_sync_w2r/*gray_meta* || \
     NAME =~ ${fifo_instance}/u_sync_w2r/*gray_sync_reg* || \
     NAME =~ ${fifo_instance}/u_sync_r2w/*gray_meta* || \
     NAME =~ ${fifo_instance}/u_sync_r2w/*gray_sync_reg*"]
set_property ASYNC_REG TRUE $fifo_sync_regs

# Do not use set_clock_groups -asynchronous for wr_clk and rd_clk in the same
# constraint scope as these paths. That command creates higher-priority timing
# exceptions which can override the Gray-bus set_max_delay constraints below.
#
# Constrain each direction with its source clock period:
#   wptr_gray (wr_clk) -> wptr_gray_meta (rd_clk)
#   rptr_gray (rd_clk) -> rptr_gray_meta (wr_clk)
set wr_period [get_property PERIOD [get_clocks wr_clk]]
set rd_period [get_property PERIOD [get_clocks rd_clk]]

set wptr_meta_pins [get_pins -quiet -hier -filter \
    "NAME =~ ${fifo_instance}/u_sync_w2r/*wptr_gray_meta_reg*/D"]
set rptr_meta_pins [get_pins -quiet -hier -filter \
    "NAME =~ ${fifo_instance}/u_sync_r2w/*rptr_gray_meta_reg*/D"]

# Discover the actual sequential startpoints feeding the first synchronizer
# stage. Vivado can merge a Gray-pointer bit with an equivalent binary-pointer
# register, so source-register name matching is not a complete constraint.
set wptr_source_regs [all_fanin -flat -startpoints_only -only_cells \
    -to $wptr_meta_pins]
set rptr_source_regs [all_fanin -flat -startpoints_only -only_cells \
    -to $rptr_meta_pins]

# XDC files accept only the constraint-command subset of Tcl, so exact object
# counts are checked by the post-synthesis companion script:
#   source constraints/xilinx/check_async_fifo.tcl
#   check_async_fifo_cdc {u_async_fifo_core} 10
# Pass the same instance path and pointer width configured above.
#
# For scripted non-project flows, constrain_async_fifo_cdc in that companion
# file performs the exact checks and applies both crossing constraints as one
# operation.

set_max_delay -datapath_only $wr_period \
    -from $wptr_source_regs -to $wptr_meta_pins
set_bus_skew $wr_period \
    -from $wptr_source_regs -to $wptr_meta_pins

set_max_delay -datapath_only $rd_period \
    -from $rptr_source_regs -to $rptr_meta_pins
set_bus_skew $rd_period \
    -from $rptr_source_regs -to $rptr_meta_pins

# report_cdc should be reviewed after synthesis/implementation:
# report_cdc -details -name async_fifo_cdc
#
# Also verify that no false-path or clock-group exception overrides these
# paths:
# report_exceptions -coverage
# report_timing -from $wptr_source_regs -to $wptr_meta_pins
# report_timing -from $rptr_source_regs -to $rptr_meta_pins
