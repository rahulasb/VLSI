view wave

add wave -divider {Clock and controls}
add wave -label clk sim:/tb_mac_lane/clk
add wave -label resetn sim:/tb_mac_lane/resetn
add wave -label load_bias sim:/tb_mac_lane/load_bias
add wave -label mac_en sim:/tb_mac_lane/mac_en

add wave -divider {Signed arithmetic}
add wave -radix decimal -label input_value sim:/tb_mac_lane/input_value
add wave -radix decimal -label weight_value sim:/tb_mac_lane/weight_value
add wave -radix decimal -label bias_value sim:/tb_mac_lane/bias_value
add wave -radix decimal -label product sim:/tb_mac_lane/dut/product

add wave -divider {Actual and expected accumulator}
add wave -radix decimal -label acc_actual sim:/tb_mac_lane/acc
add wave -radix decimal -label acc_expected sim:/tb_mac_lane/expected_acc

configure wave -namecolwidth 200
configure wave -valuecolwidth 100
configure wave -timelineunits ns

run 130 ns
wave zoom range 0ns 130ns
