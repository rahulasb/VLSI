`timescale 1ns/1ps

module tb_nn_accelerator;

    reg clk;
    reg resetn;
    reg wr_en;
    reg [5:0] addr;
    reg [7:0] data_in;
    reg start;
    reg [1:0] out_sel;

    wire [7:0] data_out;
    wire busy;
    wire done;

    // Reference storage models the external write address map.
    reg [7:0] reference_bytes [0:47];
    reg [7:0] reference_outputs [0:3];
    reg [7:0] pending_outputs [0:3];

    // Observed outputs are sampled through data_out.
    reg [7:0] observed_outputs [0:3];
    reg [7:0] expected_data_out;
    integer pending_sums [0:3];

    integer remaining;
    reg reference_done;

    integer cycles_checked;
    integer outputs_checked;
    integer accepted_starts;
    integer completed_inferences;
    integer aborted_inferences;
    integer zero_results;
    integer saturated_results;
    integer intermediate_results;
    integer start_cycle_number;
    time accepted_start_time;

    integer test_phase;
    integer index;
    integer neuron;
    integer position;
    integer trial;
    integer seed;

    nn_accelerator dut (
        .clk      (clk),
        .resetn   (resetn),
        .wr_en    (wr_en),
        .addr     (addr),
        .data_in  (data_in),
        .start    (start),
        .out_sel  (out_sel),
        .data_out (data_out),
        .busy     (busy),
        .done     (done)
    );

    // Functional simulation clock: 20 ns period.
    initial clk = 0;
    always #10 clk = ~clk;

    function automatic integer signed_byte;
        input [7:0] value;
        begin
            if (value[7])
                signed_byte = value - 256;
            else
                signed_byte = value;
        end
    endfunction

    // Independent integer dot-product calculation.
    task automatic compute_reference;
        integer n;
        integer i;
        integer total;
        integer scaled;
        reg [15:0] bias_bits;

        begin
            for (n = 0; n < 4; n = n + 1) begin
                bias_bits = {
                    reference_bytes[41 + 2*n],
                    reference_bytes[40 + 2*n]
                };

                if (bias_bits[15])
                    total = bias_bits - 65536;
                else
                    total = bias_bits;

                for (i = 0; i < 8; i = i + 1)
                    total = total
                          + signed_byte(reference_bytes[i])
                          * signed_byte(reference_bytes[8 + 8*n + i]);

                pending_sums[n] = total;

                if (total <= 0) begin
                    pending_outputs[n] = 0;
                end
                else begin
                    scaled = total / 128;

                    if (scaled > 255)
                        pending_outputs[n] = 255;
                    else
                        pending_outputs[n] = scaled;
                end
            end
        end
    endtask

    task automatic check_status;
        begin
            if ((busy !== (remaining != 0)) ||
                (done !== reference_done)) begin

                $display("FAIL: status at time %0t, phase %0d",
                         $time, test_phase);
                $display("Expected busy=%b done=%b",
                         (remaining != 0), reference_done);
                $display("Actual busy=%b done=%b", busy, done);
                $fatal(1, "Accelerator status mismatch");
            end
        end
    endtask

    // Check all four results through the actual output mux.
    task automatic check_outputs;
        integer n;
        begin
            for (n = 0; n < 4; n = n + 1) begin
                out_sel = n;
                expected_data_out = reference_outputs[n];
                #1;

                observed_outputs[n] = data_out;
                outputs_checked = outputs_checked + 1;

                if (data_out !== reference_outputs[n]) begin
                    $display("FAIL: output %0d, time %0t, phase %0d",
                             n, $time, test_phase);
                    $display("Expected=%0d actual=%0d",
                             reference_outputs[n], data_out);
                    $fatal(1, "Accelerator output mismatch");
                end
            end
        end
    endtask

    task automatic check_cycle;
        input rst;
        input start_request;
        input write_enable;
        input integer write_address;
        input integer byte_value;

        integer n;

        begin
            @(negedge clk);

            resetn = rst;
            start = start_request;
            wr_en = write_enable;
            addr = write_address;
            data_in = byte_value;

            // Registered status and outputs must remain unchanged
            // until the rising edge, including during reset.
            #1;
            check_status;
            check_outputs;

            @(posedge clk);
            #1;

            cycles_checked = cycles_checked + 1;

            if (!rst) begin
                if (remaining != 0)
                    aborted_inferences = aborted_inferences + 1;

                remaining = 0;
                reference_done = 0;

                for (n = 0; n < 48; n = n + 1)
                    reference_bytes[n] = 0;

                for (n = 0; n < 4; n = n + 1) begin
                    reference_outputs[n] = 0;
                    pending_outputs[n] = 0;
                    pending_sums[n] = 0;
                end
            end
            else if (remaining == 0) begin
                if (start_request) begin
                    // Snapshot the parameters before inference.
                    // A simultaneous write must be ignored.
                    compute_reference;

                    remaining = 9;
                    reference_done = 0;
                    accepted_starts = accepted_starts + 1;
                    start_cycle_number = cycles_checked;
                    accepted_start_time = $time;
                end
                else if (write_enable &&
                         write_address >= 0 &&
                         write_address < 48) begin

                    reference_bytes[write_address] = byte_value;
                end
            end
            else begin
                // Writes and start requests are ignored while busy.
                remaining = remaining - 1;

                if (remaining == 0) begin
                    if ((cycles_checked - start_cycle_number) != 9)
                        $fatal(1, "Incorrect completion cycle");

                    if (($time - accepted_start_time) != 180)
                        $fatal(1, "Incorrect completion time");

                    for (n = 0; n < 4; n = n + 1) begin
                        reference_outputs[n] = pending_outputs[n];

                        if (pending_outputs[n] == 0)
                            zero_results = zero_results + 1;
                        else if (pending_outputs[n] == 255)
                            saturated_results = saturated_results + 1;
                        else
                            intermediate_results =
                                intermediate_results + 1;
                    end

                    reference_done = 1;
                    completed_inferences =
                        completed_inferences + 1;
                end
            end

            check_status;
            check_outputs;
        end
    endtask

    // Mode 0: ordinary inference.
    // Mode 1: attempt writes and starts on every busy edge.
    // Mode 2: assert write and start together on the start edge.
    task automatic run_inference;
        input integer mode;
        integer step;
        integer target_address;

        begin
            check_cycle(1, 1, mode == 2, 0, 99);

            for (step = 1; step <= 9; step = step + 1) begin
                if (step == 9)
                    target_address = 47;
                else
                    target_address = (step - 1) * 6;

                check_cycle(
                    1,
                    mode == 1,
                    mode == 1,
                    target_address,
                    8'ha5
                );
            end
        end
    endtask

    // Load constant inputs and one constant weight per neuron.
    task automatic load_fixed;
        input integer x;
        input integer w0;
        input integer w1;
        input integer w2;
        input integer w3;
        input integer b0;
        input integer b1;
        input integer b2;
        input integer b3;

        integer n;
        integer i;
        integer w;
        integer b;

        begin
            for (i = 0; i < 8; i = i + 1)
                check_cycle(1, 0, 1, i, x);

            for (n = 0; n < 4; n = n + 1) begin
                case (n)
                    0: begin w = w0; b = b0; end
                    1: begin w = w1; b = b1; end
                    2: begin w = w2; b = b2; end
                    3: begin w = w3; b = b3; end
                endcase

                for (i = 0; i < 8; i = i + 1)
                    check_cycle(1, 0, 1, 8 + 8*n + i, w);

                check_cycle(1, 0, 1, 40 + 2*n, b & 255);
                check_cycle(1, 0, 1, 41 + 2*n, (b >> 8) & 255);
            end
        end
    endtask

    task automatic load_random;
        input integer full_range;
        integer n;
        integer i;
        integer value;

        begin
            for (i = 0; i < 8; i = i + 1) begin
                if (full_range)
                    value = ($random(seed) & 255) - 128;
                else
                    value = ($random(seed) & 31) - 16;

                check_cycle(1, 0, 1, i, value);
            end

            for (n = 0; n < 4; n = n + 1) begin
                for (i = 0; i < 8; i = i + 1) begin
                    if (full_range)
                        value = ($random(seed) & 255) - 128;
                    else
                        value = ($random(seed) & 31) - 16;

                    check_cycle(1, 0, 1, 8 + 8*n + i, value);
                end

                if (full_range)
                    value = ($random(seed) & 65535) - 32768;
                else
                    value = ($random(seed) & 2047) - 1024;

                check_cycle(1, 0, 1, 40 + 2*n, value & 255);
                check_cycle(1, 0, 1, 41 + 2*n,
                            (value >> 8) & 255);
            end
        end
    endtask

    // Hold each output selection for a full clock period
    // to produce a clear readback waveform.
    task automatic show_readback;
        integer n;
        begin
            for (n = 0; n < 4; n = n + 1) begin
                @(negedge clk);
                start = 0;
                wr_en = 0;
                out_sel = n;
                expected_data_out = reference_outputs[n];

                #1;
                check_status;

                if (data_out !== reference_outputs[n])
                    $fatal(1, "Readback selection mismatch");

                @(posedge clk);
                #1;
                check_status;

                if (data_out !== reference_outputs[n])
                    $fatal(1, "Readback hold mismatch");
            end
        end
    endtask

    initial begin
        resetn = 0;
        wr_en = 0;
        addr = 0;
        data_in = 0;
        start = 0;
        out_sel = 0;

        remaining = 0;
        reference_done = 0;
        expected_data_out = 0;
        cycles_checked = 0;
        outputs_checked = 0;
        accepted_starts = 0;
        completed_inferences = 0;
        aborted_inferences = 0;
        zero_results = 0;
        saturated_results = 0;
        intermediate_results = 0;
        start_cycle_number = 0;
        accepted_start_time = 0;
        seed = 32'h56789abc;

        for (index = 0; index < 48; index = index + 1)
            reference_bytes[index] = 0;

        for (neuron = 0; neuron < 4; neuron = neuron + 1) begin
            reference_outputs[neuron] = 0;
            pending_outputs[neuron] = 0;
            observed_outputs[neuron] = 0;
            pending_sums[neuron] = 0;
        end

        test_phase = 1;
        $display("TEST 1: Reset clears status and all outputs");
        check_cycle(0, 1, 1, 0, 255);
        check_cycle(1, 0, 0, 0, 0);

        test_phase = 2;
        $display("TEST 2: Four-neuron inference and output readback");
        load_fixed(16, 8, -8, 127, 16, 0, -128, 32767, 128);
        run_inference(0);

        if ({observed_outputs[0], observed_outputs[1],
             observed_outputs[2], observed_outputs[3]}
            !== {8'd8, 8'd0, 8'd255, 8'd17})
            $fatal(1, "Directed example did not match known results");

        $display("Directed example outputs: 8, 0, 255, 17");
        show_readback;

        test_phase = 3;
        $display("TEST 3: Busy rejects writes and additional starts");
        run_inference(1);
        run_inference(0);

        test_phase = 4;
        $display("TEST 4: Start takes priority over an idle write");
        run_inference(2);
        run_inference(0);

        test_phase = 5;
        $display("TEST 5: Reserved addresses and disabled writes");

        for (index = 48; index < 64; index = index + 1)
            check_cycle(1, 0, 1, index, 255);

        for (index = 0; index < 48; index = index + 1)
            check_cycle(1, 0, 0, index,
                        reference_bytes[index] ^ 8'hff);

        run_inference(0);

        test_phase = 6;
        $display("TEST 6: Partial input, bias, and weight reload");
        check_cycle(1, 0, 1, 0, 32);
        run_inference(0);

        check_cycle(1, 0, 1, 40, 0);
        check_cycle(1, 0, 1, 41, 1);
        run_inference(0);

        check_cycle(1, 0, 1, 8, -8);
        run_inference(0);

        test_phase = 7;
        $display("TEST 7: Extreme sums and independent neuron biases");
        load_fixed(-128, -128, 127, 0, 0,
                   32767, -32768, 32767, -32768);
        run_inference(0);

        load_fixed(0, 0, 0, 0, 0, 128, 256, 384, 512);
        run_inference(0);

        test_phase = 8;
        $display("TEST 8: Isolate every input and weight position");
        load_fixed(0, 0, 0, 0, 0, 0, 0, 0, 0);

        for (neuron = 0; neuron < 4; neuron = neuron + 1)
            for (index = 0; index < 8; index = index + 1)
                check_cycle(1, 0, 1, 8 + 8*neuron + index,
                            -(8*neuron + index + 1));

        for (position = 0; position < 8; position = position + 1) begin
            if (position > 0)
                check_cycle(1, 0, 1, position - 1, 0);

            check_cycle(1, 0, 1, position, -128);
            run_inference(0);
        end

        test_phase = 9;
        $display("TEST 9: Reset at every MAC position and output capture");

        for (position = 0; position <= 8; position = position + 1) begin
            load_fixed(16, 8, -8, 127, 16, 0, -128, 32767, 128);
            run_inference(0);

            check_cycle(1, 1, 0, 0, 0);

            for (index = 0; index < position; index = index + 1)
                check_cycle(1, 0, 0, 0, 0);

            check_cycle(0, 1, 1, 0, 255);

            // No delayed completion may appear after reset.
            for (index = 0; index < 12; index = index + 1)
                check_cycle(1, 0, 0, 0, 0);

            // Cleared parameters must produce four zero outputs.
            run_inference(0);
        end

        test_phase = 10;
        $display("TEST 10: 100 random parameter sets, each run twice");

        for (trial = 0; trial < 100; trial = trial + 1) begin
            load_random(trial % 2);
            run_inference(trial % 3);
            run_inference(0);
        end

        if ((zero_results == 0) ||
            (saturated_results == 0) ||
            (intermediate_results == 0))
            $fatal(1, "Required output categories were not exercised");

        if (accepted_starts !=
            completed_inferences + aborted_inferences)
            $fatal(1, "An accepted inference was not accounted for");

        $display("----------------------------------------");
        $display("PASS: Complete accelerator verification completed.");
        $display("Clock cycles checked: %0d", cycles_checked);
        $display("Output comparisons: %0d", outputs_checked);
        $display("Accepted starts: %0d", accepted_starts);
        $display("Completed inferences: %0d", completed_inferences);
        $display("Reset-aborted inferences: %0d", aborted_inferences);
        $display("Zero-valued results: %0d", zero_results);
        $display("Results equal to 255: %0d", saturated_results);
        $display("Results from 1 through 254: %0d",
                 intermediate_results);
        $display("Each completion: nine clock periods.");
        $display("----------------------------------------");

        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Simulation timeout");
    end

endmodule
