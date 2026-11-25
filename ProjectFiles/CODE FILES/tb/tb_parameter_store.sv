`timescale 1ns/1ps

module tb_parameter_store;

    reg clk;
    reg resetn;
    reg wr_en;
    reg busy;
    reg start;
    reg [5:0] addr;
    reg [7:0] data_in;
    reg [2:0] read_index;

    wire signed [7:0] input_value;
    wire signed [7:0] weights [0:3];
    wire signed [15:0] biases [0:3];

    // Independent byte-addressed reference storage.
    reg [7:0] reference_bytes [0:47];

    integer cycles_checked;
    integer readbacks_checked;
    integer test_phase;
    integer index;
    integer mode;
    integer seed;
    integer random_addr;
    integer random_data;
    integer random_enable;
    integer random_busy;
    integer random_start;

    parameter_store dut (
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

    // Functional simulation clock.
    // The period leaves time to check all eight read indices.
    initial clk = 0;
    always #10 clk = ~clk;

    task automatic check_storage;
        integer r;
        integer neuron;
        reg [15:0] expected_bias;

        begin
            for (r = 0; r < 8; r = r + 1) begin
                read_index = r;
                #1;

                if (input_value !== reference_bytes[r]) begin
                    $display("FAIL: input index %0d at time %0t",
                             r, $time);
                    $display("Expected byte=%h, actual byte=%h",
                             reference_bytes[r], input_value);
                    $fatal(1, "Input storage mismatch");
                end

                for (neuron = 0; neuron < 4;
                     neuron = neuron + 1) begin

                    if (weights[neuron] !==
                        reference_bytes[8 + 8*neuron + r]) begin

                        $display("FAIL: neuron %0d, weight %0d",
                                 neuron, r);
                        $display("Time=%0t", $time);
                        $display("Expected byte=%h, actual byte=%h",
                            reference_bytes[8 + 8*neuron + r],
                            weights[neuron]);
                        $fatal(1, "Weight storage mismatch");
                    end

                    expected_bias = {
                        reference_bytes[41 + 2*neuron],
                        reference_bytes[40 + 2*neuron]
                    };

                    if (biases[neuron] !== expected_bias) begin
                        $display("FAIL: bias neuron %0d at time %0t",
                                 neuron, $time);
                        $display("Expected=%h, actual=%h",
                                 expected_bias, biases[neuron]);
                        $fatal(1, "Bias storage mismatch");
                    end
                end

                readbacks_checked = readbacks_checked + 1;
            end
        end
    endtask

    task automatic check_cycle;
        input rst;
        input write_enable;
        input is_busy;
        input start_request;
        input integer write_address;
        input integer byte_value;

        integer b;

        begin
            @(negedge clk);

            resetn = rst;
            wr_en = write_enable;
            busy = is_busy;
            start = start_request;
            addr = write_address;
            data_in = byte_value;

            // Storage must retain its previous values before
            // the rising edge, including when reset is asserted.
            #1;
            check_storage;

            @(posedge clk);
            #1;

            if (!rst) begin
                for (b = 0; b < 48; b = b + 1)
                    reference_bytes[b] = 0;
            end
            else if (write_enable && !is_busy &&
                     !start_request &&
                     write_address >= 0 &&
                     write_address < 48) begin

                reference_bytes[write_address] = byte_value;
            end

            cycles_checked = cycles_checked + 1;
            check_storage;
        end
    endtask

    initial begin
        resetn = 0;
        wr_en = 0;
        busy = 0;
        start = 0;
        addr = 0;
        data_in = 0;
        read_index = 0;

        cycles_checked = 0;
        readbacks_checked = 0;
        test_phase = 1;
        seed = 32'h3456789a;

        for (index = 0; index < 48; index = index + 1)
            reference_bytes[index] = 0;

        $display("TEST 1: Reset and empty storage");
        check_cycle(0, 1, 1, 1, 0, 255);
        check_cycle(1, 0, 0, 0, 0, 0);

        test_phase = 2;
        $display("TEST 2: Load every input, weight, and bias byte");

        for (index = 0; index < 8; index = index + 1)
            check_cycle(1, 1, 0, 0, index,
                        (index * 37 + 128) & 255);

        for (index = 0; index < 32; index = index + 1)
            check_cycle(1, 1, 0, 0, 8 + index,
                        (index * 11 + 3) & 255);

        // Bias 0: BEEF hexadecimal, a negative signed value.
        check_cycle(1, 1, 0, 0, 40, 8'hef);
        check_cycle(1, 1, 0, 0, 41, 8'hbe);

        // Bias 1: -1.
        check_cycle(1, 1, 0, 0, 42, 8'hff);
        check_cycle(1, 1, 0, 0, 43, 8'hff);

        // Bias 2: -32768.
        check_cycle(1, 1, 0, 0, 44, 8'h00);
        check_cycle(1, 1, 0, 0, 45, 8'h80);

        // Bias 3: 32767.
        check_cycle(1, 1, 0, 0, 46, 8'hff);
        check_cycle(1, 1, 0, 0, 47, 8'h7f);

        // Update each byte separately; preserve the other byte.
        check_cycle(1, 1, 0, 0, 40, 8'h34);
        check_cycle(1, 1, 0, 0, 41, 8'h12);

        test_phase = 3;
        $display("TEST 3: Block writes using busy, start, or wr_en");

        for (mode = 0; mode < 3; mode = mode + 1) begin
            for (index = 0; index < 48; index = index + 1) begin
                check_cycle(
                    1,
                    mode != 2,
                    mode == 0,
                    mode == 1,
                    index,
                    reference_bytes[index] ^ 8'hff
                );
            end
        end

        check_cycle(1, 1, 1, 1, 0, 0);

        test_phase = 4;
        $display("TEST 4: Ignore every reserved address");

        for (index = 48; index < 64; index = index + 1)
            check_cycle(1, 1, 0, 0, index, 255);

        test_phase = 5;
        $display("TEST 5: 500 randomized loading/control cycles");

        for (index = 0; index < 500; index = index + 1) begin
            random_addr = $random(seed) & 63;
            random_data = $random(seed) & 255;
            random_enable = $random(seed) & 1;
            random_busy = (($random(seed) & 3) == 0);
            random_start = (($random(seed) & 3) == 0);

            check_cycle(
                1,
                random_enable,
                random_busy,
                random_start,
                random_addr,
                random_data
            );
        end

        test_phase = 6;
        $display("TEST 6: Reset priority and reverse-order reload");

        check_cycle(1, 1, 0, 0, 0, 255);
        check_cycle(0, 1, 1, 1, 0, 123);
        check_cycle(1, 0, 0, 0, 0, 0);

        for (index = 47; index >= 0; index = index - 1)
            check_cycle(1, 1, 0, 0, index,
                        (index * 23 + 7) & 255);

        check_cycle(1, 0, 0, 0, 0, 0);

        $display("----------------------------------------");
        $display("PASS: Parameter storage verification completed.");
        $display("Clock cycles checked: %0d", cycles_checked);
        $display("Readback groups checked: %0d", readbacks_checked);
        $display("Randomized cycles: 500");
        $display("----------------------------------------");

        $finish;
    end

    initial begin
        #50000;
        $fatal(1, "Simulation timeout");
    end

endmodule
