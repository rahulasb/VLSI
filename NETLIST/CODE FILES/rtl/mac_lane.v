`timescale 1ns/1ps

module mac_lane (
    input  wire               clk,
    input  wire               resetn,
    input  wire               load_bias,
    input  wire               mac_en,
    input  wire signed [7:0]  input_value,
    input  wire signed [7:0]  weight_value,
    input  wire signed [15:0] bias_value,

    output reg  signed [23:0] acc
);

    // Signed 8-bit operands produce a signed 16-bit product.
    wire signed [15:0] product;

    // Extend the signed product to the accumulator width.
    wire signed [23:0] extended_product;

    assign product = input_value * weight_value;

    assign extended_product = {
        {8{product[15]}},
        product
    };

    always @(posedge clk) begin
        if (!resetn) begin
            acc <= 24'sd0;
        end
        else if (load_bias) begin
            // Initialize the sum with the signed bias exactly once.
            acc <= {
                {8{bias_value[15]}},
                bias_value
            };
        end
        else if (mac_en) begin
            acc <= acc + extended_product;
        end
        // Otherwise, retain the current accumulator value.
    end

endmodule
