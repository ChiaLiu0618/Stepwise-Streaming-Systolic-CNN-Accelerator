module Controller (
                    input clk, rst_n,
                    input instruction_valid, input [15:0] instruction,

                    output reg mode,    // Conv or FC
                    output reg load_bias,       // Load Bias
                    output reg load_scale,      // Load Scaling Factor
                    output reg load_weight,     // Load Weight
                    output reg [4:0] weight_idx,
                    output reg load_activation,

                    output reg input_valid,
                    output reg [2:0] activation_channel,           
                    output reg [4:0] weight_set [0:15],      // 0~31 weight sets for 16 propagates
                    output reg MAC_end [0:7], output reg ReLU [0:7], output reg Pool
                    );

parameter NO_OP = 3'b000;                      // No operation
parameter LOAD = 3'b001;        
         // {mode[15:13], 3'b0, Weight idx[9:5], Change Mode[4], Operation Mode[3], Load Weight[2], Load Bias[1], Load Scale[0]}    // 0 = Conv, 1 = FC
parameter MAC_COMPUTE = 3'b010;                
         // {mode[15:13], Activation Channel[12:10], Weight idx[9:5], MAC[4], Store[3], ReLU[2], Pool[1], Load Activation[0]}

genvar k;
integer i, j, m;

// MODE CHANGE
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) mode <= 1'b0;
    else if(instruction_valid && instruction[15:13] == LOAD && instruction[4]) mode <= instruction[3];
    else mode <= mode;
end

// LOAD WEIGHT
always @(*) begin
    if(instruction_valid && instruction[15:13] == LOAD) begin
        load_weight = instruction[2];
        weight_idx = instruction[9:5];
    end
    else begin
        load_weight = 1'b0;
        weight_idx = 5'b0;
    end
end

// LOAD BIAS
always @(*) begin
    if(instruction_valid && instruction[15:13] == LOAD) load_bias = instruction[1];
    else load_bias = 1'b0;
end

// LOAD SCALE
always @(*) begin
    if(instruction_valid && instruction[15:13] == LOAD) load_scale = instruction[0];
    else load_scale = 1'b0;
end

// LOAD ACTIVATION
always @(*) begin
    if(instruction_valid && instruction[15:13] == MAC_COMPUTE) load_activation = instruction[0];
    else load_activation = 1'b0;
end

// MAC COMPUTE
parameter MAC_signal_delay = 18;
reg [4:0] weight_set_call;
reg [4:0] buffered_weight_set [0:MAC_signal_delay-3];

always @(*) begin
    if(instruction_valid && instruction[15:13] == MAC_COMPUTE) begin
        activation_channel = instruction[12:10];
        weight_set_call = instruction[9:5];
        input_valid = instruction[4];
    end
    else begin
        activation_channel = 3'b0;
        weight_set_call = 5'b0;
        input_valid = 1'b0;
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
    if(instruction_valid && instruction[15:13] == MAC_COMPUTE) begin
        MAC_end_call = instruction[3];
        ReLU_call = instruction[2];
        Pool_call = instruction[1];
    end
    else begin
        MAC_end_call = 1'b0;
        ReLU_call = 1'b0;
        Pool_call = 1'b0;
    end
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
