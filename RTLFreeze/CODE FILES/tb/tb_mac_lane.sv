`timescale 1ns/1ps

module tb_mac_lane;

    reg clk;
    reg resetn;
    reg load_bias;
    reg mac_en;

    reg signed [7:0]  input_value;
    reg signed [7:0]  weight_value;
    reg signed [15:0] bias_value;

    wire signed [23:0] acc;

    integer expected_acc;
    integer cycles_checked;
    integer seed;
    integer trial;
    integer index;
    integer random_input;
    integer random_weight;
    integer random_bias;

    mac_lane dut (
        .clk          (clk),
        .resetn       (resetn),
        .load_bias    (load_bias),
        .mac_en       (mac_en),
        .input_value  (input_value),
        .weight_value (weight_value),
        .bias_value   (bias_value),
        .acc          (acc)
    );

    // A 10 ns clock is used only for functional simulation.
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Drive inputs away from the active rising clock edge.
    // Compare the hardware against an integer reference model.
    task automatic check_cycle;
        input rst;
        input load;
        input enable;
        input integer x;
        input integer w;
        input integer b;

        integer reference_input;
        integer reference_weight;
        integer reference_bias;

        begin
            @(negedge clk);

            resetn       = rst;
            load_bias    = load;
            mac_en       = enable;
            input_value  = x;
            weight_value = w;
            bias_value   = b;

            // Widen signed operands before reference arithmetic.
            reference_input  = input_value;
            reference_weight = weight_value;
            reference_bias   = bias_value;

            @(posedge clk);
            #1;

            if (!rst)
                expected_acc = 0;
            else if (load)
                expected_acc = reference_bias;
            else if (enable)
                expected_acc = expected_acc
                             + reference_input * reference_weight;

            cycles_checked = cycles_checked + 1;

            if (acc !== expected_acc[23:0]) begin
                $display("FAIL at time %0t, check %0d",
                         $time, cycles_checked);
                $display("resetn=%b load_bias=%b mac_en=%b",
                         resetn, load_bias, mac_en);
                $display("input=%0d weight=%0d bias=%0d",
                         input_value, weight_value, bias_value);
                $display("Expected acc=%0d, actual acc=%0d",
                         expected_acc, $signed(acc));
                $fatal(1, "MAC verification failed");
            end
        end
    endtask

    initial begin
        resetn        = 0;
        load_bias     = 0;
        mac_en        = 0;
        input_value   = 0;
        weight_value  = 0;
        bias_value    = 0;
        expected_acc  = 0;
        cycles_checked = 0;
        seed          = 32'h12345678;

        $display("TEST 1: Reset and disabled hold");
        check_cycle(0, 0, 0, 0, 0, 0);
        check_cycle(1, 0, 0, 127, 127, 100);

        $display("TEST 2: Bias loading and signed arithmetic");
        check_cycle(1, 1, 0, 0, 0, 10);
        check_cycle(1, 0, 1, 3, -2, 0);   // 10 - 6 = 4
        check_cycle(1, 0, 1, -4, -5, 0);  // 4 + 20 = 24
        check_cycle(1, 0, 1, -7, 3, 0);   // 24 - 21 = 3
        check_cycle(1, 0, 1, 0, 127, 0);  // Remains 3
        check_cycle(1, 0, 0, 127, 127, 0);// Hold at 3

        $display("TEST 3: Negative bias and control priority");
        check_cycle(1, 1, 0, 0, 0, -100);
        check_cycle(1, 0, 1, 10, 5, 0);   // -100 + 50 = -50
        check_cycle(1, 1, 1, 127, 127, -7);// Load wins: -7
        check_cycle(0, 1, 1, 127, 127, 99);// Reset wins: 0

        $display("TEST 4: Maximum positive eight-product sum");
        check_cycle(1, 1, 0, 0, 0, 32767);
        for (index = 0; index < 8; index = index + 1)
            check_cycle(1, 0, 1, -128, -128, 0);
        // Expected final accumulator: 163839.

        $display("TEST 5: Minimum eight-product sum");
        check_cycle(1, 1, 0, 0, 0, -32768);
        for (index = 0; index < 8; index = index + 1)
            check_cycle(1, 0, 1, -128, 127, 0);
        // Expected final accumulator: -162816.

        $display("TEST 6: Reset during accumulation and restart");
        check_cycle(0, 0, 1, 50, 50, 0);
        check_cycle(1, 1, 0, 0, 0, 12);
        check_cycle(1, 0, 1, 2, 3, 0);    // 12 + 6 = 18
        check_cycle(1, 0, 0, -128, -128, -32768);

        $display("TEST 7: 100 randomized eight-product sequences");

        for (trial = 0; trial < 100; trial = trial + 1) begin
            random_bias = ($random(seed) & 32'h0000ffff) - 32768;
            check_cycle(1, 1, 0, 0, 0, random_bias);

            for (index = 0; index < 8; index = index + 1) begin
                random_input =
                    ($random(seed) & 32'h000000ff) - 128;
                random_weight =
                    ($random(seed) & 32'h000000ff) - 128;

                check_cycle(1, 0, 1,
                            random_input, random_weight, 0);
            end

            // Changing operands while disabled must not alter acc.
            check_cycle(1, 0, 0, 127, -128, 32767);
        end

        $display("----------------------------------------");
        $display("PASS: MAC lane verification completed.");
        $display("Clock cycles checked: %0d", cycles_checked);
        $display("Randomized sequences: 100");
        $display("----------------------------------------");

        $finish;
    end

    // Stop a stalled simulation instead of running indefinitely.
    initial begin
        #20000;
        $fatal(1, "Simulation timeout");
    end

endmodule
