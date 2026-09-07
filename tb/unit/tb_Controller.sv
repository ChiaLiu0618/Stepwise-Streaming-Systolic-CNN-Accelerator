`timescale 1ns/1ps
`include "Controller.sv"

module tb_Controller;
    import Instructions::*;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, instruction_valid = 0;
    instruction_t instruction = '0;
    wire mode, load_bias, load_scale, load_weight, load_activation, load_activation_bank;
    wire input_valid, activation_bank;
    wire [4:0] weight_idx;
    wire [2:0] activation_channel;
    wire [4:0] weight_set [0:15];
    wire MAC_end [0:7], ReLU [0:7], Pool;
    Controller dut (.*);
    logic [4:0] weight_history [0:15];
    bit store_history [0:18], relu_history [0:18], pool_history [0:18];
    bit expected_mode = 0;
    bit mem_enabled, ops_enabled;
    int both_count = 0, mem_only_count = 0, ops_only_count = 0;
    int unsigned rng = 32'h31415926;

    function automatic logic [31:0] random_word;
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        return rng;
    endfunction

    initial begin
        if ($bits(instruction_t) != 32 || $bits(memory_op_t) != 16 || $bits(compute_op_t) != 16)
            $fatal(1, "incorrect packet size");
        for (int cycle = 0; cycle < 300; cycle++) begin
            @(negedge clk);
            rst_n = cycle != 0 && cycle != 121;
            instruction_valid = cycle % 5 != 0;
            instruction = instruction_t'(random_word());
            #1;
            mem_enabled = rst_n && instruction_valid && instruction.mem.enable;
            ops_enabled = rst_n && instruction_valid && instruction.ops.enable;
            if (load_weight !== (mem_enabled && instruction.mem.load_weight) ||
                load_bias !== (mem_enabled && instruction.mem.load_bias) ||
                load_scale !== (mem_enabled && instruction.mem.load_scale) ||
                load_activation !== (mem_enabled && instruction.mem.load_activation) ||
                weight_idx !== (mem_enabled ? instruction.mem.weight_addr : 5'b0) ||
                load_activation_bank !== (mem_enabled && instruction.mem.activation_bank))
                $fatal(1, "memory decode mismatch at cycle %0d", cycle);
            if (input_valid !== (ops_enabled && instruction.ops.mac) ||
                activation_channel !== (ops_enabled ? instruction.ops.activation_channel : 3'b0) ||
                activation_bank !== (ops_enabled && instruction.ops.activation_bank))
                $fatal(1, "compute decode mismatch at cycle %0d", cycle);
            both_count += int'(mem_enabled && ops_enabled);
            mem_only_count += int'(mem_enabled && !ops_enabled);
            ops_only_count += int'(!mem_enabled && ops_enabled);
            @(posedge clk);
            if (!rst_n) begin
                expected_mode = 0;
                for (int n = 0; n < 16; n++) weight_history[n] = 0;
                for (int n = 0; n < 19; n++) begin
                    store_history[n] = 0;
                    relu_history[n] = 0;
                    pool_history[n] = 0;
                end
            end else begin
                if (mem_enabled && instruction.mem.set_mode) expected_mode = instruction.mem.fc_mode;
                for (int n = 15; n > 0; n--) weight_history[n] = weight_history[n-1];
                weight_history[0] = ops_enabled ? instruction.ops.weight_addr : 5'b0;
                for (int n = 18; n > 0; n--) begin
                    store_history[n] = store_history[n-1];
                    relu_history[n] = relu_history[n-1];
                    pool_history[n] = pool_history[n-1];
                end
                store_history[0] = ops_enabled && instruction.ops.store_result;
                relu_history[0] = ops_enabled && instruction.ops.relu;
                pool_history[0] = ops_enabled && instruction.ops.pool;
            end
            #1;
            if (mode !== expected_mode) $fatal(1, "mode mismatch");
            for (int n = 0; n < 16; n++)
                if (weight_set[n] !== weight_history[n]) $fatal(1, "weight delay mismatch");
            for (int n = 0; n < 8; n++)
                if (MAC_end[n] !== store_history[n+10] || ReLU[n] !== relu_history[n+10])
                    $fatal(1, "postprocessing delay mismatch");
            if (Pool !== pool_history[18]) $fatal(1, "pool delay mismatch");
        end
        if (both_count < 20 || mem_only_count < 20 || ops_only_count < 20)
            $fatal(1, "insufficient independent-slot coverage");
        $display("PASS: 300 packet cycles, independent enables, addresses, reset, mode and control delays");
        $finish;
    end
endmodule
