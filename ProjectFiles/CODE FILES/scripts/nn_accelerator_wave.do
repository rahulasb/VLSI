view wave

add wave -divider {Clock and external control}
add wave -label clk sim:/tb_nn_accelerator/clk
add wave -label resetn sim:/tb_nn_accelerator/resetn
add wave -label start sim:/tb_nn_accelerator/start
add wave -label busy sim:/tb_nn_accelerator/busy
add wave -label done sim:/tb_nn_accelerator/done

add wave -divider {Internal computation control}
add wave -radix unsigned -label read_index sim:/tb_nn_accelerator/dut/read_index
add wave -label mac_en sim:/tb_nn_accelerator/dut/mac_en
add wave -label store_outputs sim:/tb_nn_accelerator/dut/store_outputs

add wave -divider {External output readback}
add wave -radix unsigned -label out_sel sim:/tb_nn_accelerator/out_sel
add wave -radix unsigned -label data_out sim:/tb_nn_accelerator/data_out
add wave -radix unsigned -label expected_data_out sim:/tb_nn_accelerator/expected_data_out

configure wave -namecolwidth 200
configure wave -valuecolwidth 100
configure wave -timelineunits ns

run 11820 ns
wave zoom range 1000ns 1320ns
