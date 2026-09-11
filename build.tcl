# run with
# vivado -mode batch -source run_ooc_timimng.tcl -notrace -tclargs my_module
# load dcp with
# vivado <path_to_chechpoint>.dcp

# USER SETTINGS - edit these for your project

# Top-level module to synthesize
set TOP_MODULE   "top"
set XDC_FILE "./hardware/Cmod-A7-Master.xdc"

# Allow overriding TOP_MODULE from the command line
if { $argc > 0 } {
    set TOP_MODULE [lindex $argv 0]
    set XDC_FILE [lindex $argv 1]
}

# SystemVerilog / Verilog source files (edit this list)
set SV_SOURCES [concat \
    [glob "./hardware/*.sv"] \
    [glob "./hardware/interfaces/*.sv"] \
]

# Artix-7 35T part
set PART        "xc7a35tcpg236-1"

# Output/work directory
set WORK_DIR    "./vivado_build"

# Optional: number of jobs for synth/place/route
set NUM_JOBS    20

# Setup

# Capture the directory Vivado was launched from BEFORE we cd into WORK_DIR.
# All user-supplied relative paths above (SV_SOURCES, XDC_FILE, WORK_DIR
# itself) are resolved against this directory, so "./rtl/foo.sv" always
# means "rtl/foo.sv relative to where you ran vivado", regardless of what
# directory the script itself later cd's into.
set LAUNCH_DIR [pwd]

# Resolve to absolute paths now, while cwd == LAUNCH_DIR.
set WORK_DIR [file normalize [file join $LAUNCH_DIR $WORK_DIR]]
set XDC_FILE [file normalize [file join $LAUNCH_DIR $XDC_FILE]]
set SV_SOURCES_ABS [list]
foreach f $SV_SOURCES {
    lappend SV_SOURCES_ABS [file normalize [file join $LAUNCH_DIR $f]]
}
set SV_SOURCES $SV_SOURCES_ABS


# Clean up old vivado.log and vivado.jou files
foreach pattern [list "vivado*.backup.log" "vivado*.backup.jou"] {
    foreach f [glob -nocomplain -directory $LAUNCH_DIR $pattern] {
        catch { file delete -force $f }
    }
}
 
if { [file exists $WORK_DIR] } {
    foreach pattern [list "vivado.log" "vivado.jou" "vivado*.backup.log" "vivado*.backup.jou"] {
        foreach f [glob -nocomplain -directory $WORK_DIR $pattern] {
            catch { file delete -force $f }
        }
    }
    catch { file delete -force [file join $WORK_DIR ".Xil"] }
}


file mkdir $WORK_DIR
cd $WORK_DIR

set project_name "ooc_${TOP_MODULE}"

create_project $project_name . -part $PART -force

# -----------------------------------------------------------------------------
# Add sources
# -----------------------------------------------------------------------------

foreach f $SV_SOURCES {
    if { ![file exists $f] } {
        puts "ERROR: source file not found: $f"
        exit 1
    }
}

# add_files auto-detects .sv vs .v; force SystemVerilog file type explicitly
# to be safe (Vivado sometimes needs the hint for mixed-extension projects).
add_files -norecurse $SV_SOURCES
foreach f $SV_SOURCES {
    if { [string match "*.sv" $f] } {
        set_property file_type SystemVerilog [get_files $f]
    }
}

if { ![file exists $XDC_FILE] } {
    puts "ERROR: XDC file not found: $XDC_FILE"
    exit 1
}
add_files -fileset constrs_1 -norecurse $XDC_FILE

set_property top $TOP_MODULE [current_fileset]
update_compile_order -fileset sources_1

# -----------------------------------------------------------------------------
# Synthesis
# -----------------------------------------------------------------------------

synth_design -top $TOP_MODULE -part $PART

write_checkpoint -force "${TOP_MODULE}_post_synth.dcp"
report_utilization -file "${TOP_MODULE}_post_synth_utilization.rpt"
report_timing_summary -delay_type max -max_paths 10 \
    -file "${TOP_MODULE}_post_synth_timing_summary.rpt"

# -----------------------------------------------------------------------------
# Implementation
# -----------------------------------------------------------------------------

opt_design
place_design
phys_opt_design
route_design

# Generate bitstream
write_bitstream -force "${TOP_MODULE}.bit"

write_checkpoint -force "${TOP_MODULE}_post_route.dcp"

# -----------------------------------------------------------------------------
# Timing reports
# -----------------------------------------------------------------------------

report_timing_summary -delay_type max -max_paths 20 \
    -file "${TOP_MODULE}_post_route_timing_summary.rpt"

report_timing -delay_type max -max_paths 10 -sort_by group \
    -path_type full -input_pins -file "${TOP_MODULE}_post_route_timing_detail.rpt"

report_clock_utilization -file "${TOP_MODULE}_clock_utilization.rpt"
report_utilization -file "${TOP_MODULE}_post_route_utilization.rpt"

# Print WNS/TNS/WHS/THS to the console for a quick pass/fail glance
set timing_summary [report_timing_summary -delay_type max -return_string]

puts "==================================================================="
puts " OOC TIMING RESULT FOR: $TOP_MODULE"
puts "==================================================================="
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
puts " Worst setup slack (WNS): $wns ns"
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts " Worst hold slack  (WHS): $whs ns"
puts "==================================================================="
puts " Reports written to: [pwd]"
puts "   ${TOP_MODULE}_post_route_timing_summary.rpt  (start here)"
puts "   ${TOP_MODULE}_post_route_timing_detail.rpt"
puts "   ${TOP_MODULE}_post_route_utilization.rpt"
puts "   ${TOP_MODULE}_post_route.dcp"
puts "==================================================================="

if { $wns < 0 } {
    puts "WARNING: Timing NOT met (WNS = ${wns})."
} else {
    puts "Timing met (WNS = ${wns})."
}

close_project