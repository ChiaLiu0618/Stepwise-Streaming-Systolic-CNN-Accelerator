`include "Instructions.sv"

module Controller (
    input logic clk, rst_n,
    input logic instruction_valid,
    input Instructions::instruction_t instruction,
    output wire mode, load_bias, load_scale, load_weight,
    output wire [4:0] weight_idx,
    output wire load_activation, load_activation_bank,
    output wire input_valid, activation_bank,
    output wire [2:0] activation_channel,
    output wire [4:0] weight_set [0:15],
    output wire MAC_end [0:7], ReLU [0:7],
    output wire Pool
);
    Memory_Controller memory_control (
        .clk(clk), .rst_n(rst_n), .instruction_valid(instruction_valid),
        .operation(instruction.mem), .mode(mode),
        .load_bias(load_bias), .load_scale(load_scale), .load_weight(load_weight),
        .weight_idx(weight_idx), .load_activation(load_activation),
        .activation_bank(load_activation_bank)
    );
    Compute_Controller compute_control (
        .clk(clk), .rst_n(rst_n), .instruction_valid(instruction_valid),
        .operation(instruction.ops), .input_valid(input_valid),
        .activation_channel(activation_channel), .activation_bank(activation_bank),
        .weight_set(weight_set), .MAC_end(MAC_end), .ReLU(ReLU), .Pool(Pool)
    );
endmodule

module Memory_Controller (
    input logic clk, rst_n, instruction_valid,
    input Instructions::memory_op_t operation,
    output logic mode,
    output wire load_bias, load_scale, load_weight,
    output wire [4:0] weight_idx,
    output wire load_activation, activation_bank
);
    wire enabled = rst_n && instruction_valid && operation.enable;
    assign load_weight = enabled && operation.load_weight;
    assign load_bias = enabled && operation.load_bias;
    assign load_scale = enabled && operation.load_scale;
    assign load_activation = enabled && operation.load_activation;
    assign weight_idx = enabled ? operation.weight_addr : 5'b0;
    assign activation_bank = enabled && operation.activation_bank;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) mode <= 1'b0;
        else if (enabled && operation.set_mode) mode <= operation.fc_mode;
    end
endmodule

module Compute_Controller (
    input logic clk, rst_n, instruction_valid,
    input Instructions::compute_op_t operation,
    output logic input_valid, activation_bank,
    output logic [2:0] activation_channel,
    output logic [4:0] weight_set [0:15],
    output logic MAC_end [0:7], ReLU [0:7], Pool
);
    genvar k;
    integer i;
// MAC COMPUTE
parameter MAC_signal_delay = 18;
reg [4:0] weight_set_call;
reg [4:0] buffered_weight_set [0:MAC_signal_delay-3];

always @(*) begin
    activation_channel = '0;
    activation_bank = 1'b0;
    weight_set_call = '0;
    input_valid = 1'b0;
    if (rst_n && instruction_valid && operation.enable) begin
        activation_channel = operation.activation_channel;
        activation_bank = operation.activation_bank;
        weight_set_call = operation.weight_addr;
        input_valid = operation.mac;
    end
end

Signal_Buffer #(.WIDTH(5)) MAC_SB0 (
    .clk(clk),
    .rst_n(rst_n),
    .signal(weight_set_call),
    .buffered_signal(buffered_weight_set[0])
);
generate
    for(k=0; k<MAC_signal_delay-3; k=k+1) begin
        Signal_Buffer #(.WIDTH(5)) MAC_SB1 (
            .clk(clk),
            .rst_n(rst_n),
            .signal(buffered_weight_set[k]),
            .buffered_signal(buffered_weight_set[k+1])
        );
    end
endgenerate

always @(*) begin
    for(i=0; i<16; i=i+1) begin
        weight_set[i] = buffered_weight_set[i];
    end
end

// MAC END
reg MAC_end_call;
reg buffered_MAC_end [0:MAC_signal_delay-1];

reg ReLU_call;
reg buffered_ReLU [0:MAC_signal_delay-1];

reg Pool_call;
reg buffered_Pool [0:MAC_signal_delay];

always @(*) begin
    MAC_end_call = rst_n && instruction_valid && operation.enable && operation.store_result;
    ReLU_call = rst_n && instruction_valid && operation.enable && operation.relu;
    Pool_call = rst_n && instruction_valid && operation.enable && operation.pool;
end
    // END
Signal_Buffer ME_SB0(.clk(clk), .rst_n(rst_n), .signal(MAC_end_call), .buffered_signal(buffered_MAC_end[0]));
generate
    for(k=0; k<MAC_signal_delay-1; k=k+1) begin
        Signal_Buffer ME_SB1(.clk(clk), .rst_n(rst_n), .signal(buffered_MAC_end[k]), .buffered_signal(buffered_MAC_end[k+1]));
    end
endgenerate

    // ReLU
Signal_Buffer R_SB0(.clk(clk), .rst_n(rst_n), .signal(ReLU_call), .buffered_signal(buffered_ReLU[0]));
generate
    for(k=0; k<MAC_signal_delay-1; k=k+1) begin
        Signal_Buffer R_SB1(.clk(clk), .rst_n(rst_n), .signal(buffered_ReLU[k]), .buffered_signal(buffered_ReLU[k+1]));
    end
endgenerate

    // Pool
Signal_Buffer P_SB0(.clk(clk), .rst_n(rst_n), .signal(Pool_call), .buffered_signal(buffered_Pool[0]));
generate
    for(k=0; k<MAC_signal_delay; k=k+1) begin
        Signal_Buffer P_SB1(.clk(clk), .rst_n(rst_n), .signal(buffered_Pool[k]), .buffered_signal(buffered_Pool[k+1]));
    end
endgenerate

always @(*) begin
    for(i=0; i<8; i=i+1) begin
        MAC_end[i] = buffered_MAC_end[MAC_signal_delay-8+i];
        ReLU[i] = buffered_ReLU[MAC_signal_delay-8+i];
    end
    Pool = buffered_Pool[MAC_signal_delay];
end

endmodule

module Signal_Buffer #(parameter WIDTH = 1)
                    (input clk, rst_n,
                     input [WIDTH-1:0] signal,
                     output reg [WIDTH-1:0] buffered_signal);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) buffered_signal <= 0;
        else buffered_signal <= signal;
    end
endmodule
