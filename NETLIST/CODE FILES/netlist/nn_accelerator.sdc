
# Initial synthesis constraints.

# Time values are in ns for the selected technology library.



create_clock -name clk -period 20.000 [get_ports clk]



set_clock_uncertainty -setup 0.200 [get_clocks clk]

set_clock_uncertainty -hold 0.050 [get_clocks clk]

set_clock_transition 0.100 [get_clocks clk]



# All external inputs other than the clock are synchronous data/control.

set data_inputs [remove_from_collection [all_inputs] [get_ports clk]]



set_input_delay -clock clk -max 2.000 $data_inputs

set_input_delay -clock clk -min 0.200 $data_inputs

set_input_transition 0.100 $data_inputs



set_output_delay -clock clk -max 2.000 [all_outputs]

set_output_delay -clock clk -min 0.200 [all_outputs]



# Output load: 0.010 pF for the selected library's pF units.

set_load 0.010 [all_outputs]



# resetn is synchronous; its paths remain timed.

