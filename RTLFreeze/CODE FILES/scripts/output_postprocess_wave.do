view wave

add wave -divider {Signed accumulator and rescaling}
add wave -radix decimal -label acc_input sim:/tb_output_postprocess/acc
add wave -radix decimal -label scaled_value sim:/tb_output_postprocess/dut/scaled_value

add wave -divider {Unsigned output and reference}
add wave -radix unsigned -label result_actual sim:/tb_output_postprocess/result
add wave -radix unsigned -label result_expected sim:/tb_output_postprocess/expected_result

configure wave -namecolwidth 200
configure wave -valuecolwidth 100
configure wave -timelineunits ns

run 200 ns
wave zoom range 0ns 200ns
