set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]

read_verilog [list \
    [file join $repo_root rtl/core/fifo_mem.v] \
    [file join $repo_root rtl/core/wptr_full.v] \
    [file join $repo_root rtl/core/rptr_empty.v] \
    [file join $repo_root rtl/core/sync_w2r.v] \
    [file join $repo_root rtl/core/sync_r2w.v] \
    [file join $repo_root rtl/core/async_fifo_core.v] \
    [file join $repo_root rtl/async_fifo.v]]
synth_design -top async_fifo -part xc7z020clg400-1
read_xdc [file join $repo_root constraints/xilinx/async_fifo.xdc]
source [file join $repo_root constraints/xilinx/check_async_fifo.tcl]
check_async_fifo_cdc u_async_fifo_core 10

puts "PASS: generic Xilinx CDC template applied to scoped async_fifo_core instance"
