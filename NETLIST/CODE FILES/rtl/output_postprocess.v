`timescale 1ns/1ps

module output_postprocess (
    input  wire signed [23:0] acc,
    output reg         [7:0] result
);

    wire signed [23:0] scaled_value;

    // Fixed rescaling: arithmetic right shift by seven bits.
    assign scaled_value = acc >>> 7;

    always @(*) begin
        if (scaled_value < 24'sd0) begin
            // ReLU removes negative values.
            result = 8'd0;
        end
        else if (scaled_value > 24'sd255) begin
            // Clamp values above the unsigned 8-bit range.
            result = 8'd255;
        end
        else begin
            result = scaled_value[7:0];
        end
    end

endmodule
