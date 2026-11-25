`timescale 1ns/1ps

module tb_inference_controller;

    reg clk;
    reg resetn;
    reg start;

    wire busy;
    wire done;
    wire [2:0] read_index;
    wire load_bias;
    wire mac_en;
    wire store_outputs;

    // Independent reference model:
    // 0 = idle, 9 through 2 = MAC cycles, 1 = output capture.
    integer remaining;
    reg expected_done;

    integer cycles_checked;
    integer accepted_starts;
    integer completed_inferences;
    integer aborted_inferences;
    integer mac_edges;
    integer start_cycle_number;

    integer test_phase;
    integer index;
    integer abort_position;
    integer seed;
    integer random_resetn;
    integer random_start;

    inference_controller dut (
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

    initial clk = 0;
    always #5 clk = ~clk;

    task automatic check_signals;
        reg expected_busy;
        reg [2:0] expected_index;
        reg expected_load;
        reg expected_mac;
        reg expected_store;

        begin
            expected_busy = (remaining != 0);

            if (remaining > 1)
                expected_index = 9 - remaining;
            else if (remaining == 1)
                expected_index = 7;
            else
                expected_index = 0;

            expected_load =
                resetn && (remaining == 0) && start;

            expected_mac =
                resetn && (remaining > 1);

            expected_store =
                resetn && (remaining == 1);

            if ({busy, done, read_index,
                 load_bias, mac_en, store_outputs}
                !==
                {expected_busy, expected_done, expected_index,
                 expected_load, expected_mac, expected_store}) begin

                $display("FAIL at time %0t, phase %0d",
                         $time, test_phase);

                $display("busy: expected=%b actual=%b",
                         expected_busy, busy);
                $display("done: expected=%b actual=%b",
                         expected_done, done);
                $display("index: expected=%0d actual=%0d",
                         expected_index, read_index);

                $display("Enables: bias / MAC / output");
                $display("Expected: %b / %b / %b",
                         expected_load, expected_mac, expected_store);
                $display("Actual:   %b / %b / %b",
                         load_bias, mac_en, store_outputs);

                $fatal(1, "Controller signal mismatch");
            end
        end
    endtask

    task automatic check_cycle;
        input rst;
        input start_request;

        begin
            @(negedge clk);
            resetn = rst;
            start = start_request;

            // Check control outputs and ensure registered
            // status does not change before the rising edge.
            #1;
            check_signals;

            @(posedge clk);
            #1;

            cycles_checked = cycles_checked + 1;

            if (!rst) begin
                if (remaining != 0)
                    aborted_inferences = aborted_inferences + 1;

                remaining = 0;
                expected_done = 0;
                mac_edges = 0;
            end
            else if (remaining == 0) begin
                if (start_request) begin
                    remaining = 9;
                    expected_done = 0;
                    mac_edges = 0;

                    accepted_starts = accepted_starts + 1;
                    start_cycle_number = cycles_checked;
                end
            end
            else begin
                if (remaining > 1) begin
                    mac_edges = mac_edges + 1;
                end
                else begin
                    if (mac_edges != 8)
                        $fatal(1, "Incorrect number of MAC edges");

                    if ((cycles_checked - start_cycle_number) != 9)
                        $fatal(1, "Incorrect inference latency");

                    completed_inferences =
                        completed_inferences + 1;

                    expected_done = 1;
                end

                remaining = remaining - 1;
            end

            check_signals;
        end
    endtask

    initial begin
        resetn = 0;
        start = 0;

        remaining = 0;
        expected_done = 0;
        cycles_checked = 0;
        accepted_starts = 0;
        completed_inferences = 0;
        aborted_inferences = 0;
        mac_edges = 0;
        start_cycle_number = 0;

        test_phase = 1;
        seed = 32'h456789ab;

        $display("TEST 1: Reset overrides start; idle stays idle");
        check_cycle(0, 1);
        check_cycle(1, 0);
        check_cycle(1, 0);

        test_phase = 2;
        $display("TEST 2: Eight MAC operations and nine-cycle latency");
        check_cycle(1, 1);

        for (index = 0; index < 9; index = index + 1)
            check_cycle(1, 0);

        // Done must remain high while idle.
        for (index = 0; index < 3; index = index + 1)
            check_cycle(1, 0);

        test_phase = 3;
        $display("TEST 3: Ignore start on every busy edge");
        check_cycle(1, 1);

        for (index = 0; index < 9; index = index + 1)
            check_cycle(1, 1);

        test_phase = 4;
        $display("TEST 4: Accept next start on earliest idle edge");

        // The preceding call completed at E9.
        // This call requests a new inference at E10.
        check_cycle(1, 1);

        for (index = 0; index < 9; index = index + 1)
            check_cycle(1, 0);

        test_phase = 5;
        $display("TEST 5: Reset during every MAC position and capture");

        for (abort_position = 0; abort_position <= 8;
             abort_position = abort_position + 1) begin

            check_cycle(1, 1);

            for (index = 0; index < abort_position;
                 index = index + 1)
                check_cycle(1, 0);

            // Reset must abort inference even with start high.
            check_cycle(0, 1);
            check_cycle(1, 0);
        end

        test_phase = 6;
        $display("TEST 6: 1000 randomized reset/start cycles");

        for (index = 0; index < 1000; index = index + 1) begin
            random_resetn = (($random(seed) & 31) != 0);
            random_start = $random(seed) & 1;
            check_cycle(random_resetn, random_start);
        end

        // Allow any final active inference to complete.
        for (index = 0; index < 12; index = index + 1)
            check_cycle(1, 0);

        $display("----------------------------------------");
        $display("PASS: Controller verification completed.");
        $display("Clock cycles checked: %0d", cycles_checked);
        $display("Accepted starts: %0d", accepted_starts);
        $display("Completed inferences: %0d", completed_inferences);
        $display("Reset-aborted inferences: %0d", aborted_inferences);
        $display("Each completion: 8 MAC edges, 9-cycle latency.");
        $display("----------------------------------------");

        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "Simulation timeout");
    end

endmodule
