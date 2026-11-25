`timescale 1ns/1ps

module inference_controller (
    input  wire       clk,
    input  wire       resetn,
    input  wire       start,

    output wire       busy,
    output reg        done,

    output reg  [2:0] read_index,
    output wire       load_bias,
    output wire       mac_en,
    output wire       store_outputs
);

    localparam [1:0] IDLE   = 2'd0;
    localparam [1:0] MAC    = 2'd1;
    localparam [1:0] OUTPUT = 2'd2;

    reg [1:0] state;

    // Busy remains asserted throughout accumulation
    // and until the output-capture edge.
    assign busy = (state != IDLE);

    // These enables are sampled by the datapath
    // on rising clock edges.
    assign load_bias =
        resetn && (state == IDLE) && start;

    assign mac_en =
        resetn && (state == MAC);

    assign store_outputs =
        resetn && (state == OUTPUT);

    always @(posedge clk) begin
        if (!resetn) begin
            state      <= IDLE;
            read_index <= 3'd0;
            done       <= 1'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    read_index <= 3'd0;

                    if (start) begin
                        state <= MAC;
                        done  <= 1'b0;
                    end
                    // Otherwise, retain done until another
                    // accepted start or reset.
                end

                MAC: begin
                    if (read_index == 3'd7) begin
                        state <= OUTPUT;
                    end
                    else begin
                        read_index <= read_index + 3'd1;
                    end
                end

                OUTPUT: begin
                    state      <= IDLE;
                    read_index <= 3'd0;
                    done       <= 1'b1;
                end

                default: begin
                    state      <= IDLE;
                    read_index <= 3'd0;
                    done       <= 1'b0;
                end
            endcase
        end
    end

endmodule
