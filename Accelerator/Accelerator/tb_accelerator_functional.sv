`define CYCLE_TIME 2.0 // Cycle time in nanoseconds
`define PAT_NUM 3    // Number of patterns
`define MAX_LATENCY 100 // Max latency for each pattern
`define OUT_NUM 1       // The number of output for each pattern
`define SEED 5487
`include "Accelerator.sv"

module tb_accelerator_functional;

//---------------------------------------------------------------------
//   PORT DECLARATION          
//---------------------------------------------------------------------
// Output Registers
reg clk, rst_n;
reg instruction_valid;
reg [15:0] instruction;

reg signed [7:0] SRAM_weight_data [0:8][0:7];      // INT8, 9 by 8 set of weights
reg signed [15:0] SRAM_bias_data [0:3][0:7];
reg [4:0] SRAM_scaling_factor;
reg signed [7:0] SRAM_activation [0:3][0:3][0:7];     // new column of input activations

// Input Signals
reg write_valid;
reg [63:0] write_data;

//---------------------------------------------------------------------
//   PARAMETER & INTEGER DECLARATION
//---------------------------------------------------------------------
/* Parameters and Integers */
integer patnum = `PAT_NUM;
integer seed = `SEED;
parameter MAX_LATENCY = `MAX_LATENCY;
integer i_pat, j_pat;
integer latency_wait, latency_out;
integer total_latency;
integer i, j, m;
integer i_out, j_out;

parameter ROWS = 28;
parameter COLS = 28;
parameter PADDED_ROWS = 30;
parameter PADDED_COLS = 30;

integer file, status;
integer i_read, j_read;
integer i_pad, j_pad;

// ISA
parameter NO_OP = 3'b000;                      // No operation
parameter LOAD = 3'b001;        
         // {mode[15:13], 3'b0, Weight idx[9:5], Change Mode[4], Operation Mode[3], Load Weight[2], Load Bias[1], Load Scale[0]}    // 0 = Conv, 1 = FC
parameter MAC_COMPUTE = 3'b010;                
         // {mode[15:13], Activation Channel[12:10], Weight idx[9:5], MAC[4], Store[3], ReLU[2], Pool[1], Load Activation[0]}
//---------------------------------------------------------------------
//   REG & WIRE DECLARATION
//---------------------------------------------------------------------

reg [7:0] temp_data [0:COLS-1];
reg [7:0] data_matrix [0:PADDED_ROWS-1][0:PADDED_COLS-1]; // 30x30 padded image
reg [255:0] line;

reg signed [7:0] weight [0:8][0:7][0:31];    // INT8, 9 by 8, 8 set of weights
reg signed [15:0] bias [0:3][0:7];
reg [4:0] scaling_factor [0:`PAT_NUM-1];

reg [4:0] weight_idx;
reg [2:0] activation_channel;
reg signed [7:0] activation [0:3][0:3][0:31];     // INT8, 4 by 4 window, from 32 input channels
reg signed [7:0] input_data [0:3][0:8];     // flattened activation

reg signed [31:0] expected_channel_value [0:3][0:7];    // 4 cores, each 8 channels

reg signed [31:0] expected_value [0:`PAT_NUM-1][0:3][0:7];

reg [63:0] write_word [0:3][0:`PAT_NUM-1];
reg signed [7:0] output_pixel [0:3][0:7];


real weight_mult;
real input_mult;
real partial_sum;

reg end_pat_flag;


//---------------------------------------------------------------------
//  CLOCK
//---------------------------------------------------------------------
/* Define clock cycle */
real CYCLE = `CYCLE_TIME;
always #(CYCLE/2.0) clk = ~clk;

//---------------------------------------------------------------------
//  SIMULATION
//---------------------------------------------------------------------
Accelerator A1(.clk(clk), .rst_n(rst_n),
                .instruction_valid(instruction_valid), .instruction(instruction),
                
                .SRAM_activation(SRAM_activation),
                .SRAM_weight_data(SRAM_weight_data),
                .SRAM_bias_data(SRAM_bias_data),
                .SRAM_scaling_factor(SRAM_scaling_factor),

                .write_valid(write_valid), .write_data(write_data));

initial begin
    rst_n           = 1'b1;
    total_latency   = 0;
    latency_wait     = 0;
    end_pat_flag = 0;
    instruction_valid = 0;
end

/* execution */
initial begin
    `ifdef RTL
        $fsdbDumpfile("Accelerator_Functional.fsdb");
        $fsdbDumpvars(0,"+mda");
    `endif
    `ifdef GATE
        $sdf_annotate("./Netlist/Accelerator_SYN.sdf");
        $fsdbDumpfile("Accelerator_Functional_SYN.fsdb");
        $fsdbDumpvars(0,"+mda"); 
    `endif
end

initial begin
    reset_task;
    repeat (2) @(negedge clk);
    // for(i_pat = 0; i_pat < patnum; i_pat = i_pat + 1) begin
        
    // end 

    instruction_valid = 1'b1;
    instruction = {LOAD, 3'b0, 5'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0};  // change mode to Conv, don't load weight, don't load bias and scale
    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};

    i_pat = 0;
    @(negedge clk);
    generate_conv1_input_task;
    calculate_conv1_ans_task;
    input_conv1_param_task;
    input_conv1_activation_task;
    input_conv1_task;

    i_pat = i_pat + 1;
    @(negedge clk);
    generate_conv2_input_task;
    calculate_conv2_ans_task;
    input_conv2_param_task;
    input_conv2_task;

    @(negedge clk);
    instruction_valid = 1'b1;
    instruction = {LOAD, 3'b0, 5'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0};  // change mode to FC, don't load weight, don't load bias and scale
    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};

    i_pat = i_pat + 1;
    @(negedge clk);
    generate_fc_input_task;
    calculate_fc_ans_task;
    input_fc_param_task;
    input_fc_task;
end

initial begin
    // for ( j_pat = 0 ; j_pat < patnum; j_pat = j_pat + 1) begin
        
    // end
    j_pat = 0;
    $display("************************************************************");  
    $display("                        Conv1 Layer                         ");
    $display("     INPUT: 8 Channels * 9 Activations * 9 Weights          ");
    $display("     OUTPUT: 8 Output Channels * 1 Pixel (after pooling)    ");         
    $display("************************************************************");
    wait_begin_check_task;
    check_conv_ans_task;

    j_pat = j_pat + 1;
    $display("************************************************************");  
    $display("                        Conv2 Layer                         ");
    $display("     INPUT: 32 Channels * 9 Activations * 9 Weights         ");
    $display("     OUTPUT: 8 Output Channels * 1 Pixel (after pooling)    ");         
    $display("************************************************************");
    wait_begin_check_task;
    check_conv_ans_task;

    j_pat = j_pat + 1;
    $display("************************************************************");  
    $display("                    Fully Connected Layer                   ");
    $display("     INPUT: 72 Features * Weights                           ");
    $display("     OUTPUT: 32 Features                                    ");         
    $display("************************************************************");
    wait_begin_check_task;
    check_fc_ans_task;

    YOU_PASS_task;
end


// Task to reset the system
task reset_task; begin 
    rst_n = 1'b1;
    force clk = 0;

    #(CYCLE*2.0); rst_n = 1'b0; 
    #(CYCLE*2.0); rst_n = 1'b1;

    if ((write_valid !== 1'b0) || (write_data[0] !== 64'b0) || (write_data[1] !== 64'b0) 
        || (write_data[2] !== 64'b0) || (write_data[3] !== 64'b0)) begin
        $display("************************************************************");
        $display("                          FAIL!                           ");
        $display("*  Output signals should be 0 after initial RESET at %8t *", $time);
        $display("************************************************************");
        repeat (2) #CYCLE;
        $finish;
    end
    
    #(CYCLE*2.0); release clk;
end endtask

// Conv1 Task
task generate_conv1_input_task; begin
    // $display("************************************************************");  
    // $display("                        Conv1 Layer!                        ");
    // $display("     INPUT: 8 Input Channels * 9 Activations * 9 Weights    ");
    // $display("     OUTPUT:  1 Pooled Pixels * 8 Output Channels           ");         
    // $display("************************************************************");

    // GENERATE WEIGHT
    for(m=0; m<8; m=m+1) begin      // 8 sets (layers) of weights   
        // $display("************************************************************"); 
        // $display("                    Weight Set No.: %d                     ", m); 

        for(i=0; i<9; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                weight[i][j][m] = $random(seed);
            end

            // $display("%d, %d, %d, %d, %d, %d, %d, %d",
            //     weight[i][0][m], weight[i][1][m], weight[i][2][m], weight[i][3][m],
            //     weight[i][4][m], weight[i][5][m], weight[i][6][m], weight[i][7][m]);   

                                
        end
        // $display("************************************************************");
    end
    
    for(m=8; m<32; m=m+1) begin
        for(i=0; i<9; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                weight[i][j][m] = 8'b0;
            end    
        end
    end

    // GENERATE BIAS
    for(j=0; j<8; j=j+1) begin
        bias[0][j] = $random(seed);
    end

    // $display("************************************************************");
    // $display("          Bias: %d, %d, %d, %d, %d, %d, %d, %d             ",
    //         bias[0][0], bias[0][1], bias[0][2], bias[0][3],
    //         bias[0][4], bias[0][5], bias[0][6], bias[0][7]);   
    // $display("************************************************************");

    for(j=0; j<8; j=j+1) begin
        bias[1][j] = 0;
        bias[2][j] = 0;
        bias[3][j] = 0;
    end                     

    // GENERATE SCALE
    scaling_factor[i_pat] = 5'd10;

    // $display("************************************************************");
    // $display("                     Activation Scale: %d                ", scaling_factor[i_pat]);
    // $display("************************************************************");

    // GENERATE ACTIVATION
    for(m=0; m<8; m=m+1) begin      // 8 layers (channels) of activations

        // $display("Activation Channel No.: %d", m); 

        for(i=0; i<4; i=i+1) begin
            for(j=0; j<4; j=j+1) begin
                activation[i][j][m] = $random(seed);
            end

            // $display("%d, %d, %d, %d",
            //     activation[i][0][m], activation[i][1][m], activation[i][2][m], activation[i][3][m]);                        
        end
    end
end endtask

task calculate_conv1_ans_task; begin
    for(i=0; i<4; i=i+1) begin
        for(j=0; j<8; j=j+1) begin
            expected_channel_value[i][j] = bias[0][j];
        end
    end

    for(m=0; m<8; m=m+1) begin       
        // Core 1
        input_data[0][0] = activation[0][0][m];
        input_data[0][1] = activation[0][1][m];
        input_data[0][2] = activation[0][2][m];
        input_data[0][3] = activation[1][0][m];
        input_data[0][4] = activation[1][1][m];
        input_data[0][5] = activation[1][2][m];
        input_data[0][6] = activation[2][0][m];
        input_data[0][7] = activation[2][1][m];
        input_data[0][8] = activation[2][2][m];

        for(j=0; j<8; j=j+1) begin      // output channel
            partial_sum = 0;
            for(i=0; i<9; i=i+1) begin
                input_mult = input_data[0][i];
                weight_mult = weight[i][j][m];
                partial_sum = partial_sum + input_mult * weight_mult;
            end

            expected_channel_value[0][j] = expected_channel_value[0][j] + partial_sum;
        end

        // Core 2
        input_data[1][0] = activation[0][1][m];
        input_data[1][1] = activation[0][2][m];
        input_data[1][2] = activation[0][3][m];
        input_data[1][3] = activation[1][1][m];
        input_data[1][4] = activation[1][2][m];
        input_data[1][5] = activation[1][3][m];
        input_data[1][6] = activation[2][1][m];
        input_data[1][7] = activation[2][2][m];
        input_data[1][8] = activation[2][3][m];

        for(j=0; j<8; j=j+1) begin      // output channel
            partial_sum = 0;
            for(i=0; i<9; i=i+1) begin
                input_mult = input_data[1][i];
                weight_mult = weight[i][j][m];
                partial_sum = partial_sum + input_mult * weight_mult;
            end

            expected_channel_value[1][j] = expected_channel_value[1][j] + partial_sum;
        end

        // Core 3
        input_data[2][0] = activation[1][0][m];
        input_data[2][1] = activation[1][1][m];
        input_data[2][2] = activation[1][2][m];
        input_data[2][3] = activation[2][0][m];
        input_data[2][4] = activation[2][1][m];
        input_data[2][5] = activation[2][2][m];
        input_data[2][6] = activation[3][0][m];
        input_data[2][7] = activation[3][1][m];
        input_data[2][8] = activation[3][2][m];

        for(j=0; j<8; j=j+1) begin      // output channel
            partial_sum = 0;
            for(i=0; i<9; i=i+1) begin
                input_mult = input_data[2][i];
                weight_mult = weight[i][j][m];
                partial_sum = partial_sum + input_mult * weight_mult;
            end

            expected_channel_value[2][j] = expected_channel_value[2][j] + partial_sum;
        end

        // Core 4
        input_data[3][0] = activation[1][1][m];
        input_data[3][1] = activation[1][2][m];
        input_data[3][2] = activation[1][3][m];
        input_data[3][3] = activation[2][1][m];
        input_data[3][4] = activation[2][2][m];
        input_data[3][5] = activation[2][3][m];
        input_data[3][6] = activation[3][1][m];
        input_data[3][7] = activation[3][2][m];
        input_data[3][8] = activation[3][3][m];

        for(j=0; j<8; j=j+1) begin      // output channel
            partial_sum = 0;
            for(i=0; i<9; i=i+1) begin
                input_mult = input_data[3][i];
                weight_mult = weight[i][j][m];
                partial_sum = partial_sum + input_mult * weight_mult;
            end

            expected_channel_value[3][j] = expected_channel_value[3][j] + partial_sum;
        end
    end

    for(m=0; m<4; m=m+1) begin
        for(j=0; j<8; j=j+1) begin
            expected_value[i_pat][m][j] = expected_channel_value[m][j];
        end
    end
end endtask

task input_conv1_param_task; begin
    @(negedge clk);
    weight_idx = 0;
    instruction_valid = 1'b1;
    instruction = {LOAD, 3'b0, weight_idx, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0};  // don't change mode, load weight, don't load bias and scale

    for(m=0; m<8; m=m+1) begin      // 32 sets (layers) of weights, but only first 8 sets have value
        for(i=0; i<9; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                SRAM_weight_data[i][j] = weight[i][j][m];
            end
        end
        @(negedge clk);
        weight_idx = weight_idx + 1;
        instruction = {LOAD, 3'b0, weight_idx, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0};  // don't change mode, load weight, don't load param
    end

    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};
    weight_idx = 0;
    
    @(negedge clk);
    instruction_valid = 1'b1;
    instruction = {LOAD, 3'b0, 5'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1};  // don't change mode, don't load weight, load bias and scale

    for(m=0; m<4; m=m+1) begin
        for(j=0; j<8; j=j+1) begin
            SRAM_bias_data[m][j] = bias[0][j];
        end
    end

    SRAM_scaling_factor = scaling_factor[i_pat];

    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};
end endtask

task input_conv1_activation_task; begin
    @(negedge clk);
    instruction_valid = 1'b1;
    instruction = {MAC_COMPUTE, 3'b0, 5'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1};  
        // Dont't compute, Don't store, No ReLU, No Pool, Load Activation

    for(j=0; j<4; j=j+1) begin      // 4 columns
        for(m=0; m<8; m=m+1) begin      // 8 sets (layers) of Activations
            for(i=0; i<4; i=i+1) begin
                SRAM_activation[i][j][m] = activation[i][j][m];
            end
        end
    end

    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};
end endtask

task input_conv1_task; begin
    for(m=0; m<8; m=m+1) begin
        @(negedge clk);
        instruction_valid = 1'b1;
        activation_channel = m;
        weight_idx = m;

        if(m==7) instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0};  // Compute, Store, ReLU, Pool, Don't load Activation
        else instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0};  // Compute, Don't store, No ReLU, No Pool, Don't load Activation
    end

    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};

    repeat(18) @(negedge clk);
end endtask

// Conv2 Task
task generate_conv2_input_task; begin
    // $display("************************************************************");  
    // $display("                        Conv2 Layer!                        ");
    // $display("                      32 Input Channels                      ");         
    // $display("************************************************************");

    // GENERATE WEIGHT
    for(m=0; m<32; m=m+1) begin      // 32 sets (layers) of weights   
        // $display("************************************************************"); 
        // $display("                    Weight Set No.: %d                     ", m); 

        for(i=0; i<9; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                weight[i][j][m] = $random(seed);
            end

            // $display("%d, %d, %d, %d, %d, %d, %d, %d",
            //     weight[i][0][m], weight[i][1][m], weight[i][2][m], weight[i][3][m],
            //     weight[i][4][m], weight[i][5][m], weight[i][6][m], weight[i][7][m]);    
        end
        // $display("************************************************************");
    end

    // GENERATE BIAS
    for(j=0; j<8; j=j+1) begin
        bias[0][j] = $random(seed);
    end

    // $display("************************************************************");
    // $display("          Bias: %d, %d, %d, %d, %d, %d, %d, %d             ",
    //         bias[0][0], bias[0][1], bias[0][2], bias[0][3],
    //         bias[0][4], bias[0][5], bias[0][6], bias[0][7]);   
    // $display("************************************************************");

    for(j=0; j<8; j=j+1) begin
        bias[1][j] = 0;
        bias[2][j] = 0;
        bias[3][j] = 0;
    end                     

    // GENERATE SCALE
    scaling_factor[i_pat] = 5'd11;

    // $display("************************************************************");
    // $display("                     Activation Scale: %d                ", scaling_factor[i_pat]);
    // $display("************************************************************");

    // GENERATE ACTIVATION
    for(m=0; m<32; m=m+1) begin      // 32 layers (channels) of activations

        // $display("Activation Channel No.: %d", m); 

        for(i=0; i<4; i=i+1) begin
            for(j=0; j<4; j=j+1) begin
                activation[i][j][m] = $random(seed);
            end

            // $display("%d, %d, %d, %d",
            //     activation[i][0][m], activation[i][1][m], activation[i][2][m], activation[i][3][m]);                        
        end
    end
end endtask

task calculate_conv2_ans_task; begin
    for(i=0; i<4; i=i+1) begin
        for(j=0; j<8; j=j+1) begin
            expected_channel_value[i][j] = bias[0][j];
        end
    end

    for(m=0; m<32; m=m+1) begin       
        // Core 1
        input_data[0][0] = activation[0][0][m];
        input_data[0][1] = activation[0][1][m];
        input_data[0][2] = activation[0][2][m];
        input_data[0][3] = activation[1][0][m];
        input_data[0][4] = activation[1][1][m];
        input_data[0][5] = activation[1][2][m];
        input_data[0][6] = activation[2][0][m];
        input_data[0][7] = activation[2][1][m];
        input_data[0][8] = activation[2][2][m];

        for(j=0; j<8; j=j+1) begin      // output channel
            partial_sum = 0;
            for(i=0; i<9; i=i+1) begin
                input_mult = input_data[0][i];
                weight_mult = weight[i][j][m];
                partial_sum = partial_sum + input_mult * weight_mult;
            end

            expected_channel_value[0][j] = expected_channel_value[0][j] + partial_sum;
        end

        // Core 2
        input_data[1][0] = activation[0][1][m];
        input_data[1][1] = activation[0][2][m];
        input_data[1][2] = activation[0][3][m];
        input_data[1][3] = activation[1][1][m];
        input_data[1][4] = activation[1][2][m];
        input_data[1][5] = activation[1][3][m];
        input_data[1][6] = activation[2][1][m];
        input_data[1][7] = activation[2][2][m];
        input_data[1][8] = activation[2][3][m];

        for(j=0; j<8; j=j+1) begin      // output channel
            partial_sum = 0;
            for(i=0; i<9; i=i+1) begin
                input_mult = input_data[1][i];
                weight_mult = weight[i][j][m];
                partial_sum = partial_sum + input_mult * weight_mult;
            end

            expected_channel_value[1][j] = expected_channel_value[1][j] + partial_sum;
        end

        // Core 3
        input_data[2][0] = activation[1][0][m];
        input_data[2][1] = activation[1][1][m];
        input_data[2][2] = activation[1][2][m];
        input_data[2][3] = activation[2][0][m];
        input_data[2][4] = activation[2][1][m];
        input_data[2][5] = activation[2][2][m];
        input_data[2][6] = activation[3][0][m];
        input_data[2][7] = activation[3][1][m];
        input_data[2][8] = activation[3][2][m];

        for(j=0; j<8; j=j+1) begin      // output channel
            partial_sum = 0;
            for(i=0; i<9; i=i+1) begin
                input_mult = input_data[2][i];
                weight_mult = weight[i][j][m];
                partial_sum = partial_sum + input_mult * weight_mult;
            end

            expected_channel_value[2][j] = expected_channel_value[2][j] + partial_sum;
        end

        // Core 4
        input_data[3][0] = activation[1][1][m];
        input_data[3][1] = activation[1][2][m];
        input_data[3][2] = activation[1][3][m];
        input_data[3][3] = activation[2][1][m];
        input_data[3][4] = activation[2][2][m];
        input_data[3][5] = activation[2][3][m];
        input_data[3][6] = activation[3][1][m];
        input_data[3][7] = activation[3][2][m];
        input_data[3][8] = activation[3][3][m];

        for(j=0; j<8; j=j+1) begin      // output channel
            partial_sum = 0;
            for(i=0; i<9; i=i+1) begin
                input_mult = input_data[3][i];
                weight_mult = weight[i][j][m];
                partial_sum = partial_sum + input_mult * weight_mult;
            end

            expected_channel_value[3][j] = expected_channel_value[3][j] + partial_sum;
        end
    end

    for(m=0; m<4; m=m+1) begin
        for(j=0; j<8; j=j+1) begin
            expected_value[i_pat][m][j] = expected_channel_value[m][j];
        end
    end
end endtask

task input_conv2_param_task; begin
    @(negedge clk);
    weight_idx = 0;
    instruction_valid = 1'b1;
    instruction = {LOAD, 3'b0, weight_idx, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0};  // don't change mode, load weight, don't load param

    for(m=0; m<32; m=m+1) begin      // 32 sets (layers) of weights
        for(i=0; i<9; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                SRAM_weight_data[i][j] = weight[i][j][m];
            end
        end
        @(negedge clk);
        weight_idx = weight_idx + 1;
        instruction = {LOAD, 3'b0, weight_idx, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0};  // don't change mode, load weight, don't load param
    end

    weight_idx = 0;
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};

    @(negedge clk);
    instruction_valid = 1'b1;
    instruction = {LOAD, 3'b0, 5'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1};  // don't change mode, don't load weight, load bias and scale

    for(m=0; m<4; m=m+1) begin
        for(j=0; j<8; j=j+1) begin
            SRAM_bias_data[m][j] = bias[0][j];
        end
    end

    SRAM_scaling_factor = scaling_factor[i_pat];

    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};
end endtask

task input_conv2_task; begin
    // First 8 channels
    @(negedge clk);
    instruction_valid = 1'b1;
    instruction = {MAC_COMPUTE, 3'b0, 5'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1};  // Dont't compute, Don't store, No ReLU, No Pool, Load Activation
    for(j=0; j<4; j=j+1) begin      // 4 columns
        for(m=0; m<8; m=m+1) begin      // 8 sets (layers) of Activations
            for(i=0; i<4; i=i+1) begin
                SRAM_activation[i][j][m] = activation[i][j][m];
            end
        end
    end
    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};
    
    for(m=0; m<7; m=m+1) begin
        @(negedge clk);
        instruction_valid = 1'b1;  
        activation_channel = m;
        weight_idx = m;
        instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0};  // Compute, Don't store, No ReLU, No Pool, Don't load Activation
    end

    @(negedge clk);
    instruction_valid = 1'b1;
    activation_channel = 3'd7;
    weight_idx = 5'd7;
    instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1};  // Compute, Don't store, No ReLU, No Pool, Load Activation
    for(j=0; j<4; j=j+1) begin      // 4 columns
        for(m=0; m<8; m=m+1) begin      // 8 sets (layers) of Activations
            for(i=0; i<4; i=i+1) begin
                SRAM_activation[i][j][m] = activation[i][j][m+8];
            end
        end    
    end

    // Second 8 channels
    for(m=0; m<7; m=m+1) begin
        @(negedge clk);
        instruction_valid = 1'b1;
        activation_channel = m;
        weight_idx = m+8;
        instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0};  // Compute, Don't store, No ReLU, No Pool, Don't load Activation
    end

    @(negedge clk);
    instruction_valid = 1'b1;
    activation_channel = 3'd7;
    weight_idx = 5'd15;
    instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1};  // Compute, Don't store, No ReLU, No Pool, Load Activation
    for(j=0; j<4; j=j+1) begin      // 4 columns
        for(m=0; m<8; m=m+1) begin      // 8 sets (layers) of Activations
            for(i=0; i<4; i=i+1) begin
                SRAM_activation[i][j][m] = activation[i][j][m+16];
            end
        end
    end
    
    // Third 8 channels
    for(m=0; m<7; m=m+1) begin
        @(negedge clk);
        instruction_valid = 1'b1;
        activation_channel = m;
        weight_idx = m+16;
        instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0};  // Compute, Don't store, No ReLU, No Pool, Don't load Activation
    end

    @(negedge clk);
    instruction_valid = 1'b1;
    activation_channel = 3'd7;
    weight_idx = 5'd23;
    instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1};  // Compute, Don't store, No ReLU, No Pool, Load Activation
    for(j=0; j<4; j=j+1) begin      // 4 columns
        for(m=0; m<8; m=m+1) begin      // 8 sets (layers) of Activations
            for(i=0; i<4; i=i+1) begin
                SRAM_activation[i][j][m] = activation[i][j][m+24];
            end
        end
    end
    
    // Fourth 8 channels
    for(m=0; m<8; m=m+1) begin
        @(negedge clk);
        instruction_valid = 1'b1;
        activation_channel = m;
        weight_idx = m+24;

        if(m==7) instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0};  // Compute, Store, ReLU, Pool, Don't load Activation
        else instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0};  // Compute, Don't store, No ReLU, No Pool, Don't load Activation
    end

    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};

    repeat(18) @(negedge clk);
end endtask

// FC Task
task generate_fc_input_task; begin
    // $display("************************************************************");  
    // $display("                   Fully Connected Layer                    ");
    // $display("                     72 Input Features                      ");         
    // $display("************************************************************");

    // GENERATE WEIGHT
    for(m=0; m<32; m=m+1) begin      // 32 sets (layers) of weights   
        // $display("************************************************************"); 
        // $display("                    Weight Set No.: %d                     ", m); 

        for(i=0; i<9; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                weight[i][j][m] = $random(seed);
            end

            // $display("%d, %d, %d, %d, %d, %d, %d, %d",
            //     weight[i][0][m], weight[i][1][m], weight[i][2][m], weight[i][3][m],
            //     weight[i][4][m], weight[i][5][m], weight[i][6][m], weight[i][7][m]);    
        end
        // $display("************************************************************");
    end

    // GENERATE BIAS
    for(j=0; j<8; j=j+1) begin
        bias[0][j] = $random(seed);
        bias[1][j] = $random(seed);
        bias[2][j] = $random(seed);
        bias[3][j] = $random(seed);
    end

    // $display("************************************************************");
    // $display("          Bias: %d, %d, %d, %d, %d, %d, %d, %d             ",
    //         bias[0][0], bias[0][1], bias[0][2], bias[0][3],
    //         bias[0][4], bias[0][5], bias[0][6], bias[0][7]);   
    // $display("************************************************************");               

    // GENERATE SCALE
    scaling_factor[i_pat] = 5'd10;

    // $display("************************************************************");
    // $display("                     Activation Scale: %d                ", scaling_factor[i_pat]);
    // $display("************************************************************");

    // GENERATE ACTIVATION
    for(m=0; m<8; m=m+1) begin      // 8 layers (channels) of activations

        // $display("Activation Channel No.: %d", m); 

        for(i=0; i<3; i=i+1) begin
            for(j=0; j<3; j=j+1) begin
                activation[i][j][m] = $random(seed);
            end
            activation[i][3][m] = 0;

            // $display("%d, %d, %d, %d",
            //     activation[i][0][m], activation[i][1][m], activation[i][2][m], activation[i][3][m]);                        
        end
        for(j=0; j<4; j=j+1) begin
            activation[3][j][m] = 0;
        end
        // $display("%d, %d, %d, %d",
        //     activation[3][0][m], activation[3][1][m], activation[3][2][m], activation[3][3][m]); 
    end
end endtask

task calculate_fc_ans_task; begin
    for(i=0; i<4; i=i+1) begin
        for(j=0; j<8; j=j+1) begin
            expected_channel_value[i][j] = bias[i][j];
        end
    end

    for(m=0; m<8; m=m+1) begin      
        input_data[0][0] = activation[0][0][m];
        input_data[0][1] = activation[0][1][m];
        input_data[0][2] = activation[0][2][m];
        input_data[0][3] = activation[1][0][m];
        input_data[0][4] = activation[1][1][m];
        input_data[0][5] = activation[1][2][m];
        input_data[0][6] = activation[2][0][m];
        input_data[0][7] = activation[2][1][m];
        input_data[0][8] = activation[2][2][m];

        // Core 1
        for(j=0; j<8; j=j+1) begin      // output channel
            partial_sum = 0;
            for(i=0; i<9; i=i+1) begin
                input_mult = input_data[0][i];
                weight_mult = weight[i][j][m+0];
                partial_sum = partial_sum + input_mult * weight_mult;
            end

            expected_channel_value[0][j] = expected_channel_value[0][j] + partial_sum;
        end

        // Core 2
        for(j=0; j<8; j=j+1) begin      // output channel
            partial_sum = 0;
            for(i=0; i<9; i=i+1) begin
                input_mult = input_data[0][i];
                weight_mult = weight[i][j][m+8];
                partial_sum = partial_sum + input_mult * weight_mult;
            end

            expected_channel_value[1][j] = expected_channel_value[1][j] + partial_sum;
        end

        // Core 3
        for(j=0; j<8; j=j+1) begin      // output channel
            partial_sum = 0;
            for(i=0; i<9; i=i+1) begin
                input_mult = input_data[0][i];
                weight_mult = weight[i][j][m+16];
                partial_sum = partial_sum + input_mult * weight_mult;
            end

            expected_channel_value[2][j] = expected_channel_value[2][j] + partial_sum;
        end

        // Core 4
        for(j=0; j<8; j=j+1) begin      // output channel
            partial_sum = 0;
            for(i=0; i<9; i=i+1) begin
                input_mult = input_data[0][i];
                weight_mult = weight[i][j][m+24];
                partial_sum = partial_sum + input_mult * weight_mult;
            end

            expected_channel_value[3][j] = expected_channel_value[3][j] + partial_sum;
        end
    end

    for(m=0; m<4; m=m+1) begin
        for(j=0; j<8; j=j+1) begin
            expected_value[i_pat][m][j] = expected_channel_value[m][j];
        end
    end
end endtask

task input_fc_param_task; begin
    @(negedge clk);
    weight_idx = 0;
    instruction_valid = 1'b1;
        instruction = {LOAD, 3'b0, weight_idx, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0};  // don't change mode, load weight, don't load param

    for(m=0; m<32; m=m+1) begin      // 32 sets (layers) of weights
        for(i=0; i<9; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                SRAM_weight_data[i][j] = weight[i][j][m];
            end
        end
        @(negedge clk);
        weight_idx = weight_idx + 1;
        instruction = {LOAD, 3'b0, weight_idx, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0};  // don't change mode, load weight, don't load param
    end

    weight_idx = 0;
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};

    @(negedge clk);
    instruction_valid = 1'b1;
        instruction = {LOAD, 3'b0, 5'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1};  // don't change mode, don't load weight, load bias and scale

    for(m=0; m<4; m=m+1) begin
        for(j=0; j<8; j=j+1) begin
            SRAM_bias_data[m][j] = bias[m][j];
        end
    end

    SRAM_scaling_factor = scaling_factor[i_pat];

    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};
end endtask

task input_fc_task; begin
    // First 8 channels
    @(negedge clk);
    instruction_valid = 1'b1;
    instruction = {MAC_COMPUTE, 3'b0, 5'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1};  // Dont't compute, Don't store, No ReLU, No Pool, Load Activation
    for(j=0; j<4; j=j+1) begin      // 4 columns
        for(m=0; m<8; m=m+1) begin      // 8 sets (layers) of Activations
            for(i=0; i<4; i=i+1) begin
                SRAM_activation[i][j][m] = activation[i][j][m];
            end
        end
    end
    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};
    
    for(m=0; m<8; m=m+1) begin
        @(negedge clk);
        instruction_valid = 1'b1;
        activation_channel = m;
        weight_idx = m;

        if(m==7) instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0};  // Compute, Store, No ReLU, No Pool, Don't load Activation
        else instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0};  // Compute, Don't store, No ReLU, No Pool, Don't load Activation
    end

    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};

    repeat(18) @(negedge clk);
end endtask


// Check Task
task wait_begin_check_task; begin
    latency_wait = 0;
    while(write_valid !== 1) begin
        if(latency_out > MAX_LATENCY) begin
            $display("************************************************************");
            $display("                          FAIL!                           ");
            $display("                   Exceed Max Latency !!" );
            $display("************************************************************");
            $finish;
        end
		@(negedge clk);
		latency_wait = latency_wait + 1;
	end
end endtask

task check_conv_ans_task; begin
    latency_out = 0;
    if(write_valid == 1'b1) begin
        write_word[0][j_pat] = write_data;
        $display("************************************************************");  
        $display("                        SRAM Write!                        ");
        $display(" Received Word:  = %h", write_word[0][j_pat]);         
        $display("************************************************************");
    end

    for(j_out=0; j_out<8; j_out=j_out+1) begin
        output_pixel[0][j_out] = write_word[0][j_pat][(63 - j_out*8) -: 8];
        $display("************************************************************");  
        $display("                       End of Case!                        ");
        $display(" Output Channel No.:  = %d", j_out);               
        $display(" Expected:  = %d, %d, %d, %d", expected_value[j_pat][0][j_out], expected_value[j_pat][1][j_out],
                                                expected_value[j_pat][2][j_out], expected_value[j_pat][3][j_out] );
        $display(" Quantized:  = %d, %d, %d, %d", expected_value[j_pat][0][j_out] >>> scaling_factor[j_pat],
                                                 expected_value[j_pat][1][j_out] >>> scaling_factor[j_pat], 
                                                 expected_value[j_pat][2][j_out] >>> scaling_factor[j_pat],
                                                 expected_value[j_pat][3][j_out] >>> scaling_factor[j_pat]);                        
        $display(" Received:  = %d (Pooled)", output_pixel[0][j_out]);         
        $display("************************************************************");
        @(negedge clk); 
        latency_out = latency_out + 1;
    end
    total_latency = total_latency + latency_wait + latency_out;
end endtask

task check_fc_ans_task; begin
    latency_out = 0;
    if(write_valid == 1'b1) begin
        for(j_out=0; j_out<4; j_out=j_out+1) begin
            write_word[j_out][j_pat] = write_data;
            $display("************************************************************");  
            $display("                        SRAM Write!                        ");
            $display(" Received Word:  = %h", write_word[j_out][j_pat]);         
            $display("************************************************************");
            @(negedge clk);
        end
    end

    for(j_out=0; j_out<8; j_out=j_out+1) begin
        output_pixel[0][j_out] = write_word[0][j_pat][(63 - j_out*8) -: 8];
        output_pixel[1][j_out] = write_word[1][j_pat][(63 - j_out*8) -: 8];
        output_pixel[2][j_out] = write_word[2][j_pat][(63 - j_out*8) -: 8];
        output_pixel[3][j_out] = write_word[3][j_pat][(63 - j_out*8) -: 8];
        $display("************************************************************");  
        $display("                       End of Case!                        ");
        $display(" Output Column No.:  = %d", j_out);               
        $display(" Expected:  = %d, %d, %d, %d", expected_value[j_pat][0][j_out], expected_value[j_pat][1][j_out],
                                                expected_value[j_pat][2][j_out], expected_value[j_pat][3][j_out] );
        $display(" Quantized:  = %d, %d, %d, %d", expected_value[j_pat][0][j_out] >>> scaling_factor[j_pat],
                                                 expected_value[j_pat][1][j_out] >>> scaling_factor[j_pat], 
                                                 expected_value[j_pat][2][j_out] >>> scaling_factor[j_pat],
                                                 expected_value[j_pat][3][j_out] >>> scaling_factor[j_pat]);                        
        $display(" Received:  = %d, %d, %d, %d", output_pixel[0][j_out], output_pixel[1][j_out],
                                                 output_pixel[2][j_out], output_pixel[3][j_out]);         
        $display("************************************************************");
        @(negedge clk); 
        latency_out = latency_out + 1;
    end
    total_latency = total_latency + latency_wait + latency_out;
end endtask

task YOU_PASS_task; begin    
    $display("----------------------------------------------------------------------------------------------------------------------");
    $display("                                                  Congratulations!                                                    ");
    $display("                                           You have passed all patterns!                                               ");
    $display("                                           Your execution cycles = %5d cycles                                          ", total_latency);
    $display("                                           Your clock period = %.1f ns                                                 ", CYCLE);
    $display("                                           Total Latency = %.1f ns                                                    ", total_latency * CYCLE);               
    $display("----------------------------------------------------------------------------------------------------------------------");
    repeat (2) @(negedge clk);
    $finish;
end endtask
endmodule