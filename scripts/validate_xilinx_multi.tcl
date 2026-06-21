set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]

read_verilog [list \
    [file join $repo_root rtl/async_reset_sync.v] \
    [file join $repo_root rtl/core/fifo_mem.v] \
    [file join $repo_root rtl/core/wptr_full.v] \
    [file join $repo_root rtl/core/rptr_empty.v] \
    [file join $repo_root rtl/core/sync_w2r.v] \
    [file join $repo_root rtl/core/sync_r2w.v] \
    [file join $repo_root rtl/core/async_fifo_core.v] \
    [file join $repo_root rtl/async_fifo.v] \
    [file join $repo_root test/xilinx/multi_fifo_top.v]]
synth_design -top multi_fifo_top -part xc7z020clg400-1

create_clock -name small_wr_clk -period 8.000 [get_ports small_wr_clk]
create_clock -name small_rd_clk -period 11.000 [get_ports small_rd_clk]
create_clock -name large_wr_clk -period 13.000 [get_ports large_wr_clk]
create_clock -name large_rd_clk -period 17.000 [get_ports large_rd_clk]

source [file join $repo_root constraints/xilinx/check_async_fifo.tcl]

constrain_async_fifo_cdc \
    u_fifo_small/u_async_fifo_core 4 small_wr_clk small_rd_clk
constrain_async_fifo_cdc \
    u_fifo_large/u_async_fifo_core 6 large_wr_clk large_rd_clk

if {![catch {
    check_async_fifo_cdc u_fifo_small/u_async_fifo_core 5
} message]} {
    error "wrong pointer width unexpectedly passed"
}
puts "PASS: wrong pointer width is rejected ($message)"

if {![catch {
    check_async_fifo_cdc u_fifo_missing/u_async_fifo_core 4
} message]} {
    error "missing instance unexpectedly passed"
}
puts "PASS: missing FIFO instance is rejected ($message)"

if {![catch {
    check_async_fifo_cdc u_fifo_*/u_async_fifo_core 4
} message]} {
    error "ambiguous wildcard scope unexpectedly passed"
}
puts "PASS: ambiguous FIFO scope is rejected ($message)"

puts "PASS: multi-instance Xilinx CDC constraints are isolated and complete"
