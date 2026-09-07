`timescale 1ns/1ps
`include "Accelerator.sv"

module tb_prefetch;
    import Instructions::*;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, instruction_valid = 0;
    instruction_t instruction = '0;
    logic signed [7:0] SRAM_activation [0:3][0:3][0:7];
    logic signed [7:0] SRAM_weight_data [0:8][0:7];
    logic signed [15:0] SRAM_bias_data [0:3][0:7];
    logic [4:0] SRAM_scaling_factor = 2;
    wire write_valid;
    wire [63:0] write_data;
    Accelerator dut (.*);

    bit fc;
    int received;
    int total_checked = 0;
    int issue_cycles;
    int serial_cycles [0:1];
    logic [63:0] reference_words [0:7];
    bit overlap;

    // Independent integer model: four channels, nine products/channel,
    // activation 1 or 2, weight lane+1 or lane+2, arithmetic scale by 2.
    always @(negedge clk) begin
        if (rst_n && write_valid) begin
            int job, lane, expected_byte;
            logic [63:0] expected_word;
            job = fc ? received / 4 : received;
            lane = fc ? received % 4 : 0;
            if (job > 1) $fatal(1, "unexpected extra output");
            expected_byte = job == 0 ? 9*(lane+1) : 18*(lane+2);
            if (expected_byte > 127) expected_byte = 127;
            expected_word = {8{8'(expected_byte)}};
            if (write_data !== expected_word)
                $fatal(1, "fc=%0d overlap=%0d word=%0d got=%h expected=%h",
                       fc, overlap, received, write_data, expected_word);
            if (!overlap) reference_words[received] = write_data;
            else if (write_data !== reference_words[received])
                $fatal(1, "prefetch differs from serial execution");
            received++;
            total_checked++;
        end
    end

    task automatic drive(input memory_op_t mem, input compute_op_t ops);
        @(negedge clk);
        #1;
        instruction_valid = 1;
        instruction = pack_instruction(mem, ops);
        issue_cycles++;
    endtask

    task automatic set_weights(input int value);
        for (int row = 0; row < 9; row++)
            for (int col = 0; col < 8; col++)
                SRAM_weight_data[row][col] = 8'(value);
    endtask

    task automatic set_activations(input int value);
        for (int row = 0; row < 4; row++)
            for (int col = 0; col < 4; col++)
                for (int ch = 0; ch < 8; ch++)
                    SRAM_activation[row][col][ch] = 8'(value);
    endtask

    task automatic drain;
        drive('0, '0);
        repeat (35) @(negedge clk);
        #1;
    endtask

    task automatic run_case(input bit fc_mode, input bit prefetch);
        memory_op_t mem;
        int pages;
        @(negedge clk);
        #1;
        rst_n = 0;
        instruction_valid = 0;
        instruction = '0;
        fc = fc_mode;
        overlap = prefetch;
        received = 0;
        issue_cycles = 0;
        pages = fc ? 4 : 1;
        for (int a = 0; a < 4; a++)
            for (int c = 0; c < 8; c++) SRAM_bias_data[a][c] = 0;
        repeat (2) @(negedge clk);
        #1 rst_n = 1;
        drive(memory_op(0, 0, 1, 1, 0, 0, 1, fc), '0);
        for (int page = 0; page < pages; page++) begin
            drive(memory_op(5'(8*page), 1, 0, 0, page == 0, 0, 0, 0), '0);
            set_weights(page+1);
            set_activations(1);
        end
        // First job reads page 0 and bank 0 while prefetch fills page 1 and bank 1.
        for (int channel = 0; channel < 4; channel++) begin
            mem = '0;
            if (prefetch && channel < pages)
                mem = memory_op(5'(1+8*channel), 1, 0, 0, channel == 0, 1, 0, 0);
            drive(mem, compute_op(3'(channel), 0, 1, channel == 3, 0, !fc, 0));
            set_weights(channel+2);
            set_activations(2);
        end
        drain();
        if (received != (fc ? 4 : 1)) $fatal(1, "first job timed out");
        if (!prefetch) begin
            for (int page = 0; page < pages; page++) begin
                drive(memory_op(5'(1+8*page), 1, 0, 0, page == 0, 1, 0, 0), '0);
                set_weights(page+2);
                set_activations(2);
            end
        end
        for (int channel = 0; channel < 4; channel++)
            drive('0, compute_op(3'(channel), 1, 1, channel == 3, 0, !fc, 1));
        drain();
        if (received != (fc ? 8 : 2)) $fatal(1, "second job timed out");
        if (!prefetch) serial_cycles[fc] = issue_cycles;
        else if (serial_cycles[fc] - issue_cycles != pages)
            $fatal(1, "prefetch did not eliminate the memory-only issue cycles");
    endtask

    initial begin
        run_case(0, 0);
        run_case(0, 1);
        run_case(1, 0);
        run_case(1, 1);
        if (total_checked != 20) $fatal(1, "incomplete output coverage");
        $display("PASS: serial/prefetch Conv and FC, 20 golden words, independent addresses and activation banks");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "timeout");
    end
endmodule
