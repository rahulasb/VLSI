`timescale 1ns/1ps

module nn_accelerator (
    input  wire       clk,
    input  wire       resetn,

    input  wire       wr_en,
    input  wire [5:0] addr,
    input  wire [7:0] data_in,

    input  wire       start,
    input  wire [1:0] out_sel,

    output wire [7:0] data_out,
    output wire       busy,
    output wire       done
);

    // Shared controller signals.
    wire [2:0] read_index;
    wire load_bias;
    wire mac_en;
    wire store_outputs;

    // Selected input is shared by all four neurons.
    wire signed [7:0] input_value;

    // Each neuron has its own weight, bias, and accumulator.
    wire signed [7:0]  weights [0:3];
    wire signed [15:0] biases  [0:3];
    wire signed [23:0] accumulators [0:3];

    wire [7:0] processed_results [0:3];
    reg  [7:0] output_regs [0:3];

    integer i;
    genvar neuron;

    inference_controller u_controller (
        .clk           (clk),
        .resetn        (resetn),
        .start         (start),
        .busy          (busy),
        .done          (done),
        .read_index    (read_index),
        .load_bias     (load_bias),
        .mac_en        (mac_en),
        .store_outputs (store_outputs)
    );

    parameter_store u_parameter_store (
        .clk         (clk),
        .resetn      (resetn),
        .wr_en       (wr_en),
        .busy        (busy),
        .start       (start),
        .addr        (addr),
        .data_in     (data_in),
        .read_index  (read_index),
        .input_value (input_value),

        .weight_0    (weights[0]),
        .weight_1    (weights[1]),
        .weight_2    (weights[2]),
        .weight_3    (weights[3]),

        .bias_0      (biases[0]),
        .bias_1      (biases[1]),
        .bias_2      (biases[2]),
        .bias_3      (biases[3])
    );

    // Generate four physical MAC and postprocessing instances.
    generate
        for (neuron = 0; neuron < 4; neuron = neuron + 1) begin
            : neuron_lanes

            mac_lane u_mac (
                .clk          (clk),
                .resetn       (resetn),
                .load_bias    (load_bias),
                .mac_en       (mac_en),
                .input_value  (input_value),
                .weight_value (weights[neuron]),
                .bias_value   (biases[neuron]),
                .acc          (accumulators[neuron])
            );

            output_postprocess u_postprocess (
                .acc    (accumulators[neuron]),
                .result (processed_results[neuron])
            );
        end
    endgenerate

    // Capture all four outputs together at completion.
    always @(posedge clk) begin
        if (!resetn) begin
            for (i = 0; i < 4; i = i + 1)
                output_regs[i] <= 8'd0;
        end
        else if (store_outputs) begin
            for (i = 0; i < 4; i = i + 1)
                output_regs[i] <= processed_results[i];
        end
        // Preserve previous outputs during loading and inference.
    end

    // Combinational readback of one stored output at a time.
    assign data_out = output_regs[out_sel];

endmodule
