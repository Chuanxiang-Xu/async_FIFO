# Post-synthesis validation for constraints/xilinx/async_fifo.xdc.
# Source this file after read_xdc, then call:
#   check_async_fifo_cdc <exact async_fifo_core hierarchy> <ADDR_WIDTH + 1>

proc require_count {objects expected description} {
    set actual [llength $objects]
    if {$actual != $expected} {
        error "$description matched $actual objects; expected $expected"
    }
}

proc check_async_fifo_cdc {fifo_instance fifo_pointer_width} {
    set fifo_instance_cells [get_cells -quiet $fifo_instance]
    require_count $fifo_instance_cells 1 \
        "FIFO scope '$fifo_instance'"

    set fifo_sync_regs [get_cells -quiet -hier -filter \
        "NAME =~ ${fifo_instance}/u_sync_w2r/*gray_meta* || \
         NAME =~ ${fifo_instance}/u_sync_w2r/*gray_sync_reg* || \
         NAME =~ ${fifo_instance}/u_sync_r2w/*gray_meta* || \
         NAME =~ ${fifo_instance}/u_sync_r2w/*gray_sync_reg*"]
    require_count $fifo_sync_regs [expr {4 * $fifo_pointer_width}] \
        "FIFO scope '$fifo_instance' synchronizer registers"

    set wptr_meta_pins [get_pins -quiet -hier -filter \
        "NAME =~ ${fifo_instance}/u_sync_w2r/*wptr_gray_meta_reg*/D"]
    set rptr_meta_pins [get_pins -quiet -hier -filter \
        "NAME =~ ${fifo_instance}/u_sync_r2w/*rptr_gray_meta_reg*/D"]
    require_count $wptr_meta_pins $fifo_pointer_width \
        "FIFO scope '$fifo_instance' write-pointer first-stage D pins"
    require_count $rptr_meta_pins $fifo_pointer_width \
        "FIFO scope '$fifo_instance' read-pointer first-stage D pins"

    set wptr_source_regs [all_fanin -flat -startpoints_only -only_cells \
        -to $wptr_meta_pins]
    set rptr_source_regs [all_fanin -flat -startpoints_only -only_cells \
        -to $rptr_meta_pins]
    require_count $wptr_source_regs $fifo_pointer_width \
        "FIFO scope '$fifo_instance' write-pointer startpoints"
    require_count $rptr_source_regs $fifo_pointer_width \
        "FIFO scope '$fifo_instance' read-pointer startpoints"

    puts "PASS: scoped FIFO CDC collections are complete for '$fifo_instance'"
}

proc constrain_async_fifo_cdc {
    fifo_instance fifo_pointer_width wr_clock rd_clock
} {
    check_async_fifo_cdc $fifo_instance $fifo_pointer_width

    set wptr_meta_pins [get_pins -quiet -hier -filter \
        "NAME =~ ${fifo_instance}/u_sync_w2r/*wptr_gray_meta_reg*/D"]
    set rptr_meta_pins [get_pins -quiet -hier -filter \
        "NAME =~ ${fifo_instance}/u_sync_r2w/*rptr_gray_meta_reg*/D"]
    set wptr_source_regs [all_fanin -flat -startpoints_only -only_cells \
        -to $wptr_meta_pins]
    set rptr_source_regs [all_fanin -flat -startpoints_only -only_cells \
        -to $rptr_meta_pins]

    set wr_period [get_property PERIOD [get_clocks $wr_clock]]
    set rd_period [get_property PERIOD [get_clocks $rd_clock]]
    if {$wr_period eq "" || $rd_period eq ""} {
        error "FIFO scope '$fifo_instance' requires valid write/read clocks"
    }

    set fifo_sync_regs [get_cells -quiet -hier -filter \
        "NAME =~ ${fifo_instance}/u_sync_w2r/*gray_meta* || \
         NAME =~ ${fifo_instance}/u_sync_w2r/*gray_sync_reg* || \
         NAME =~ ${fifo_instance}/u_sync_r2w/*gray_meta* || \
         NAME =~ ${fifo_instance}/u_sync_r2w/*gray_sync_reg*"]
    set_property ASYNC_REG TRUE $fifo_sync_regs

    set_max_delay -datapath_only $wr_period \
        -from $wptr_source_regs -to $wptr_meta_pins
    set_bus_skew $wr_period \
        -from $wptr_source_regs -to $wptr_meta_pins
    set_max_delay -datapath_only $rd_period \
        -from $rptr_source_regs -to $rptr_meta_pins
    set_bus_skew $rd_period \
        -from $rptr_source_regs -to $rptr_meta_pins

    puts "PASS: scoped FIFO CDC constraints applied to '$fifo_instance'"
}
