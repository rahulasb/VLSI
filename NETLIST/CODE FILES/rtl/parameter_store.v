`timescale 1ns/1ps

module parameter_store (
    input  wire               clk,
    input  wire               resetn,

    // External loading interface and write protection.
    input  wire               wr_en,
    input  wire               busy,
    input  wire               start,
    input  wire [5:0]         addr,
    input  wire [7:0]         data_in,

    // Shared input index for the four MAC lanes.
    input  wire [2:0]         read_index,

    output wire signed [7:0]  input_value,
    output wire signed [7:0]  weight_0,
    output wire signed [7:0]  weight_1,
    output wire signed [7:0]  weight_2,
    output wire signed [7:0]  weight_3,

    output wire signed [15:0] bias_0,
    output wire signed [15:0] bias_1,
    output wire signed [15:0] bias_2,
    output wire signed [15:0] bias_3
);

    reg signed [7:0]  input_regs  [0:7];
    reg signed [7:0]  weight_regs [0:31];
    reg signed [15:0] bias_regs   [0:3];

    integer i;

    always @(posedge clk) begin
        if (!resetn) begin
            for (i = 0; i < 8; i = i + 1)
                input_regs[i] <= 8'sd0;

            for (i = 0; i < 32; i = i + 1)
                weight_regs[i] <= 8'sd0;

            for (i = 0; i < 4; i = i + 1)
                bias_regs[i] <= 16'sd0;
        end
        else if (wr_en && !busy && !start) begin
            if (addr < 6'd8) begin
                input_regs[addr[2:0]] <= data_in;
            end
            else if (addr < 6'd40) begin
                weight_regs[addr - 6'd8] <= data_in;
            end
            else begin
                case (addr)
                    6'd40: bias_regs[0][7:0]  <= data_in;
                    6'd41: bias_regs[0][15:8] <= data_in;

                    6'd42: bias_regs[1][7:0]  <= data_in;
                    6'd43: bias_regs[1][15:8] <= data_in;

                    6'd44: bias_regs[2][7:0]  <= data_in;
                    6'd45: bias_regs[2][15:8] <= data_in;

                    6'd46: bias_regs[3][7:0]  <= data_in;
                    6'd47: bias_regs[3][15:8] <= data_in;

                    default: begin
                        // Reserved addresses have no effect.
                    end
                endcase
            end
        end
        // Otherwise, preserve all stored values.
    end

    // Combinational selection of the current input.
    assign input_value = input_regs[read_index];

    // Four banks, with eight weights in each bank.
    // Concatenation forms the five-bit weight-array index.
    assign weight_0 = weight_regs[{2'd0, read_index}];
    assign weight_1 = weight_regs[{2'd1, read_index}];
    assign weight_2 = weight_regs[{2'd2, read_index}];
    assign weight_3 = weight_regs[{2'd3, read_index}];

    assign bias_0 = bias_regs[0];
    assign bias_1 = bias_regs[1];
    assign bias_2 = bias_regs[2];
    assign bias_3 = bias_regs[3];

endmodule
