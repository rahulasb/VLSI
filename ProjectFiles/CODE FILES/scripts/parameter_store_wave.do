view wave

add wave -divider {Clock and write controls}
add wave -label clk sim:/tb_parameter_store/clk
add wave -label resetn sim:/tb_parameter_store/resetn
add wave -label wr_en sim:/tb_parameter_store/wr_en
add wave -label busy sim:/tb_parameter_store/busy
add wave -label start sim:/tb_parameter_store/start

add wave -divider {Byte loading interface}
add wave -radix unsigned -label write_address sim:/tb_parameter_store/addr
add wave -radix hexadecimal -label data_in_hex sim:/tb_parameter_store/data_in

add wave -divider {Stored signed biases}
add wave -radix decimal -label bias_0 sim:/tb_parameter_store/dut/bias_0
add wave -radix decimal -label bias_1 sim:/tb_parameter_store/dut/bias_1
add wave -radix decimal -label bias_2 sim:/tb_parameter_store/dut/bias_2
add wave -radix decimal -label bias_3 sim:/tb_parameter_store/dut/bias_3

configure wave -namecolwidth 200
configure wave -valuecolwidth 100
configure wave -timelineunits ns

run 2080 ns
wave zoom range 840ns 1060ns
