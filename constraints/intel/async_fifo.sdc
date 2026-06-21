# Intel Quartus/TimeQuest constraint template for this repository.
# Review all collection matches against the synthesized design before use.

# Replace periods and port names with top-level project values.
create_clock -name wr_clk -period 10.000 [get_ports {wr_clk}]
create_clock -name rd_clk -period 14.000 [get_ports {rd_clk}]

# Do not use set_clock_groups -asynchronous for wr_clk and rd_clk in the same
# constraint scope as these paths. It can override the Gray-bus max-delay
# constraints below.
#
# Quartus hierarchy separators and register suffixes can vary. Inspect the
# post-map names and adapt these collections before relying on the template.
set wptr_source_regs [get_registers {*|u_wptr_full:*|*wptr_gray*}]
set wptr_meta_regs [get_registers {*|u_sync_w2r:*|*wptr_gray_meta*}]

set rptr_source_regs [get_registers {*|u_rptr_empty:*|*rptr_gray*}]
set rptr_meta_regs [get_registers {*|u_sync_r2w:*|*rptr_gray_meta*}]

if {([get_collection_size $wptr_source_regs] > 0) && \
    ([get_collection_size $wptr_meta_regs] > 0)} {
    set_max_delay -datapath_only 10.000 \
        -from $wptr_source_regs -to $wptr_meta_regs
} else {
    post_message -type warning \
        "write-pointer Gray-path patterns matched no registers"
}

if {([get_collection_size $rptr_source_regs] > 0) && \
    ([get_collection_size $rptr_meta_regs] > 0)} {
    set_max_delay -datapath_only 14.000 \
        -from $rptr_source_regs -to $rptr_meta_regs
} else {
    post_message -type warning \
        "read-pointer Gray-path patterns matched no registers"
}

# Mark synchronizer registers in the project assignment file or Assignment
# Editor when the target family requires additional synchronizer identification.
# Run Report Metastability and review all unconstrained-path and exception
# reports. Confirm that no false-path or clock-group exception overrides these
# two max-delay constraints.
