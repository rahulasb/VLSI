view wave

add wave -divider {Clock and requests}
add wave -label clk sim:/tb_inference_controller/clk
add wave -label resetn sim:/tb_inference_controller/resetn
add wave -label start sim:/tb_inference_controller/start

add wave -divider {Controller status}
add wave -label busy sim:/tb_inference_controller/busy
add wave -label done sim:/tb_inference_controller/done
add wave -radix unsigned -label read_index sim:/tb_inference_controller/read_index

add wave -divider {Datapath enables}
add wave -label load_bias sim:/tb_inference_controller/load_bias
add wave -label mac_en sim:/tb_inference_controller/mac_en
add wave -label store_outputs sim:/tb_inference_controller/store_outputs

configure wave -namecolwidth 200
configure wave -valuecolwidth 100
configure wave -timelineunits ns

run 370 ns
wave zoom range 20ns 155ns
