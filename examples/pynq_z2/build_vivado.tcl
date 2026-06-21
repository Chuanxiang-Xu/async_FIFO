# Build the PYNQ-Z2 asynchronous FIFO validation design and generate reports.
# Usage:
#   vivado -mode batch -source examples/pynq_z2/build_vivado.tcl

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ../..]]
set build_dir  [file join $script_dir build]
set report_dir [file join $script_dir reports]

set pointer_width 10
source [file join $repo_root constraints/xilinx/check_async_fifo.tcl]

proc require_nonnegative_slack {delay_type} {
    set paths [get_timing_paths -quiet -delay_type $delay_type -max_paths 1]
    if {[llength $paths] == 0} {
        error "no $delay_type timing path was available for sign-off"
    }
    set slack [get_property SLACK [lindex $paths 0]]
    if {$slack < 0.0} {
        error "$delay_type timing failed with worst slack $slack ns"
    }
    puts "Verified $delay_type worst slack: $slack ns"
}

file mkdir $build_dir
file mkdir $report_dir

create_project -force async_fifo_pynq_z2 $build_dir \
    -part xc7z020clg400-1

add_files [list \
    [file join $repo_root rtl/async_reset_sync.v] \
    [file join $repo_root rtl/core/fifo_mem.v] \
    [file join $repo_root rtl/core/wptr_full.v] \
    [file join $repo_root rtl/core/rptr_empty.v] \
    [file join $repo_root rtl/core/sync_w2r.v] \
    [file join $repo_root rtl/core/sync_r2w.v] \
    [file join $repo_root rtl/core/async_fifo_core.v] \
    [file join $repo_root rtl/async_fifo.v] \
    [file join $script_dir async_fifo_pynq_z2_top.v]]

add_files -fileset constrs_1 \
    [file join $script_dir async_fifo_pynq_z2.xdc]

set_property top async_fifo_pynq_z2_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    error "synth_1 failed: $synth_status"
}

open_run synth_1
check_async_fifo_cdc u_async_fifo/u_async_fifo_core $pointer_width
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
report_cdc -details -file [file join $report_dir post_synth_cdc.rpt]
report_exceptions -coverage \
    -file [file join $report_dir post_synth_exceptions.rpt]
close_design

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status]} {
    error "impl_1 failed: $impl_status"
}

open_run impl_1
check_async_fifo_cdc u_async_fifo/u_async_fifo_core $pointer_width
report_timing_summary -file [file join $report_dir post_route_timing.rpt]
report_cdc -details -file [file join $report_dir post_route_cdc.rpt]
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
report_clock_interaction -file \
    [file join $report_dir post_route_clock_interaction.rpt]
report_exceptions -coverage \
    -file [file join $report_dir post_route_exceptions.rpt]

set bus_skew_report [file join $report_dir post_route_bus_skew.rpt]
report_bus_skew -warn_on_violation -file $bus_skew_report
set bus_skew_handle [open $bus_skew_report r]
set bus_skew_text [read $bus_skew_handle]
close $bus_skew_handle
if {[regexp -nocase {VIOLATED|Slack\s*\(FAIL} $bus_skew_text]} {
    error "Gray bus-skew requirement failed; inspect $bus_skew_report"
}

require_nonnegative_slack min
require_nonnegative_slack max

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $drc_errors] != 0} {
    error "implementation contains [llength $drc_errors] DRC errors"
}

set bitstream [file join $build_dir async_fifo_pynq_z2.runs impl_1 \
    async_fifo_pynq_z2_top.bit]
if {![file exists $bitstream]} {
    error "implementation completed without expected bitstream: $bitstream"
}

write_checkpoint -force [file join $report_dir async_fifo_pynq_z2_routed.dcp]
puts "PYNQ-Z2 FIFO implementation complete. Reports: $report_dir"
