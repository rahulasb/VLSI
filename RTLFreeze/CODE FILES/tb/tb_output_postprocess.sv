`timescale 1ns/1ps

module tb_output_postprocess;

    reg signed [23:0] acc;
    wire [7:0] result;

    integer expected_result;
    integer tests_checked;
    integer test_phase;
    integer boundary;
    integer index;
    integer seed;
    integer random_value;

    output_postprocess dut (
        .acc    (acc),
        .result (result)
    );

    // Reference calculation uses integer division instead of
    // duplicating the hardware's arithmetic-shift expression.
    task automatic check_value;
        input integer value;

        begin
            acc = value;

            if (value <= 0) begin
                expected_result = 0;
            end
            else begin
                expected_result = value / 128;

                if (expected_result > 255)
                    expected_result = 255;
            end

            // Allow combinational logic to settle.
            #1;

            tests_checked = tests_checked + 1;

            if (result !== expected_result[7:0]) begin
                $display("FAIL at time %0t, test %0d",
                         $time, tests_checked);
                $display("Accumulator=%0d", $signed(acc));
                $display("Expected result=%0d, actual result=%0d",
                         expected_result, result);
                $fatal(1, "Postprocessing verification failed");
            end

            // Keep each test value visible for ten nanoseconds.
            #9;
        end
    endtask

    initial begin
        acc             = 0;
        expected_result = 0;
        tests_checked   = 0;
        test_phase      = 1;
        seed            = 32'h23456789;

        $display("TEST 1: Directed arithmetic and boundary cases");

        // Negative inputs must produce zero.
        check_value(-8388608); // Minimum signed 24-bit value.
        check_value(-162816);  // Minimum reachable inference sum.
        check_value(-129);
        check_value(-128);
        check_value(-1);

        // Zero and small positive values.
        check_value(0);
        check_value(1);
        check_value(127);      // Output 0.
        check_value(128);      // Output 1.
        check_value(129);      // Output 1.
        check_value(255);      // Output 1.
        check_value(256);      // Output 2.
        check_value(1024);     // Output 8.

        // Upper output boundary and saturation.
        check_value(32639);    // Output 254.
        check_value(32640);    // Output 255.
        check_value(32767);    // Output 255.
        check_value(32768);    // Rescaled 256, saturated to 255.
        check_value(32896);    // Rescaled 257, saturated to 255.
        check_value(163839);   // Maximum reachable inference sum.
        check_value(8388607);  // Maximum signed 24-bit value.

        test_phase = 2;
        $display("TEST 2: Sweep every output-transition boundary");

        // Test immediately below, at, and above each multiple
        // of 128, including the transition into saturation.
        for (boundary = 0; boundary <= 256;
             boundary = boundary + 1) begin

            check_value(boundary * 128 - 1);
            check_value(boundary * 128);
            check_value(boundary * 128 + 1);
        end

        test_phase = 3;
        $display("TEST 3: 1000 randomized signed 24-bit inputs");

        for (index = 0; index < 1000; index = index + 1) begin
            random_value =
                ($random(seed) & 32'h00ffffff) - 8388608;

            check_value(random_value);
        end

        $display("----------------------------------------");
        $display("PASS: Postprocessing verification completed.");
        $display("Input values checked: %0d", tests_checked);
        $display("Directed cases: 20");
        $display("Boundary cases: 771");
        $display("Randomized cases: 1000");
        $display("----------------------------------------");

        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "Simulation timeout");
    end

endmodule
