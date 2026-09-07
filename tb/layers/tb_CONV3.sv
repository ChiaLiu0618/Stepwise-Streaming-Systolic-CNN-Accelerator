`define CYCLE_TIME 2.0 // Cycle time in nanoseconds
`define PAT_NUM 3    // Number of patterns
`define MAX_LATENCY 10000 // Max latency for each pattern
`define OUT_NUM 1       // The number of output for each pattern
`define SEED 5487
`include "Accelerator.sv"

module tb_CONV3;

//---------------------------------------------------------------------
//   PORT DECLARATION          
//---------------------------------------------------------------------
// Output Registers
reg clk, rst_n;
reg instruction_valid;
import Instructions::*;
instruction_t instruction;

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
integer i_pixel, j_pixel;
integer i_next, j_next;
integer i_out, j_out;


parameter IN_ROWS = 6;
parameter IN_COLS = 6;
parameter PAD_ROWS = 6;
parameter PAD_COLS = 6;

integer status;
integer outfile;
integer file, row, col, page, r, temp;

// ISA
//---------------------------------------------------------------------
//   REG & WIRE DECLARATION
//---------------------------------------------------------------------

reg signed [7:0] image [0:PAD_ROWS-1][0:PAD_COLS-1][0:15]; // Padded image
string line;
reg [63:0] temp_data [0:IN_COLS-1];

reg signed [7:0] weight [0:8][0:15][0:15];    // INT8, 9 weights, 16 output channels, 16 page of weights
reg signed [15:0] bias [0:3][0:15];
reg [4:0] scaling_factor;

reg [4:0] weight_idx;
reg [2:0] activation_channel;

reg [63:0] write_word_tile1 [0:5][0:5];
reg [63:0] write_word_tile2 [0:5][0:5];

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
    end_pat_flag = 0;
    instruction_valid = 0;
end

/* execution */
initial begin
    `ifdef RTL
        $fsdbDumpfile("CONV3.fsdb");
        $fsdbDumpvars(0,"+mda");
    `endif
    `ifdef GATE
        $sdf_annotate("./Netlist/Accelerator_SYN.sdf");
        $fsdbDumpfile("CONV3_SYN.fsdb");
        $fsdbDumpvars(0,"+mda"); 
    `endif
end

initial begin
    reset_task;
    repeat (2) @(negedge clk);
    // for(i_pat = 0; i_pat < patnum; i_pat = i_pat + 1) begin
        
    // end 

    instruction_valid = 1'b1;
    instruction = pack_instruction(memory_op(5'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0), '0);  
        // change mode to Conv, don't load weight, don't load bias and scale
    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = '0;

    i_pat = 0;
    @(negedge clk);
    read_image_task;
    generate_conv3_param_task;
    input_conv3_param_tile1_task;
    
    input_conv3_activation_task;
    for(i_pixel = 0; i_pixel < 2; i_pixel = i_pixel + 1) begin
        for(j_pixel = 0; j_pixel < 2; j_pixel = j_pixel + 1) begin
            input_conv3_task;
        end
    end

    repeat(18) @(negedge clk);

    input_conv3_param_tile2_task;
    
    input_conv3_activation_task;
    for(i_pixel = 0; i_pixel < 2; i_pixel = i_pixel + 1) begin
        for(j_pixel = 0; j_pixel < 2; j_pixel = j_pixel + 1) begin
            input_conv3_task;
        end
    end

    repeat(18) @(negedge clk);
end

initial begin
    // for ( j_pat = 0 ; j_pat < patnum; j_pat = j_pat + 1) begin
        
    // end
    $display("************************************************************");  
    $display("                    Conv3 Layer (Tile 1)                    ");
    $display("     INPUT: 16 IFMAPS * 6 * 6 Pixels (No Padding)           ");
    $display("     OUTPUT: First 8 OFMAPS * 2 * 2 Pixels (ReLU + Pooled)  ");         
    $display("************************************************************");

    for(i_out = 0; i_out < 2; i_out = i_out + 1) begin
        for(j_out = 0; j_out < 2; j_out = j_out + 1) begin
            wait_begin_check_task;
            check_conv_ans_tile1_task;
        end
    end

    $display("************************************************************");  
    $display("                    Conv2 Layer (Tile 2)                    ");
    $display("     INPUT: 16 IFMAPS * 6 * 6 Pixels (No Padding)           ");
    $display("     OUTPUT: Second 8 OFMAPS * 2 * 2 Pixels (ReLU + Pooled) ");         
    $display("************************************************************");

    for(i_out = 0; i_out < 2; i_out = i_out + 1) begin
        for(j_out = 0; j_out < 2; j_out = j_out + 1) begin
            wait_begin_check_task;
            check_conv_ans_tile2_task;
        end
    end

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
   
task read_image_task; begin
    // Zero all pixels first (optional)
    for (i = 0; i < IN_ROWS; i = i + 1)
        for (j = 0; j < IN_COLS; j = j + 1)
            for (m = 0; m < 16; m = m + 1)
                image[i][j][m] = 8'd0;
    
    // First Image
    file = $fopen("CONV2_Tile1_OF_Map.txt", "r");
    if (file == 0) begin
        $display("Error: Failed to open CONV2_Tile1_OF_Map.txt");
        $finish;
    end

    // Load 6×6 image directly (no +1 offsets)
    for (i = 0; i < IN_ROWS; i = i + 1) begin
        if (!$feof(file)) begin
            status = $fgets(line, file);
            if (status != 0) begin
                status = $sscanf(line,
                    "%h %h %h %h %h %h",
                    temp_data[0], temp_data[1], temp_data[2], temp_data[3],
                    temp_data[4], temp_data[5]);
                if (status == IN_COLS) begin
                    for (j = 0; j < IN_COLS; j = j + 1) begin
                        image[i][j][0] = temp_data[j][63:56];
                        image[i][j][1] = temp_data[j][55:48];
                        image[i][j][2] = temp_data[j][47:40];
                        image[i][j][3] = temp_data[j][39:32];
                        image[i][j][4] = temp_data[j][31:24];
                        image[i][j][5] = temp_data[j][23:16];
                        image[i][j][6] = temp_data[j][15:8];
                        image[i][j][7] = temp_data[j][7:0];
                    end
                end else begin
                    $fatal(1, "Error parsing row %0d", i);
                end
            end
        end
    end

    $fclose(file);

    // Second Image
    file = $fopen("CONV2_Tile2_OF_Map.txt", "r");
    if (file == 0) begin
        $display("Error: Failed to open CONV2_Tile2_OF_Map.txt");
        $finish;
    end

    // Load 6×6 image directly (no +1 offsets)
    for (i = 0; i < IN_ROWS; i = i + 1) begin
        if (!$feof(file)) begin
            status = $fgets(line, file);
            if (status != 0) begin
                status = $sscanf(line,
                    "%h %h %h %h %h %h",
                    temp_data[0], temp_data[1], temp_data[2], temp_data[3],
                    temp_data[4], temp_data[5]);
                if (status == IN_COLS) begin
                    for (j = 0; j < IN_COLS; j = j + 1) begin
                        image[i][j][8] = temp_data[j][63:56];
                        image[i][j][9] = temp_data[j][55:48];
                        image[i][j][10] = temp_data[j][47:40];
                        image[i][j][11] = temp_data[j][39:32];
                        image[i][j][12] = temp_data[j][31:24];
                        image[i][j][13] = temp_data[j][23:16];
                        image[i][j][14] = temp_data[j][15:8];
                        image[i][j][15] = temp_data[j][7:0];
                    end
                end else begin
                    $fatal(1, "Error parsing row %0d", i);
                end
            end
        end
    end

    $fclose(file);
end endtask


// Conv3 Task
task generate_conv3_param_task; begin
    // GENERATE WEIGHT
    file = $fopen("conv3_weights_tb.txt", "r");
    if (file == 0) begin
      $display("Failed to open file!");
      $finish;
    end
  
    for (page = 0; page < 16; page = page + 1) begin
      for (row = 0; row < 9; row = row + 1) begin
        for (col = 0; col < 16; col = col + 1) begin
          r = $fscanf(file, "%d", temp);
          weight[row][col][page] = temp;
        end
      end
    end
  
    $fclose(file);

    // for (page = 0; page < 8; page = page + 1) begin
    //     for (row = 0; row < 9; row = row + 1) begin
    //         for (col = 0; col < 16; col = col + 1) begin
    //             $display("weight[%0d][%0d][%0d] = %0d", row, col, page, weight[row][col][page]);
    //         end
    //     end
    // end

    // GENERATE BIAS
    for(m=0; m<4; m=m+1) begin
        bias[m][0]  = -16'sd5;
        bias[m][1]  =  16'sd69;
        bias[m][2]  =  16'sd51;
        bias[m][3]  =  16'sd52;
        bias[m][4]  = -16'sd3;
        bias[m][5]  = -16'sd6;
        bias[m][6]  =  16'sd49;
        bias[m][7]  =  16'sd49;
        bias[m][8]  =  16'sd70;
        bias[m][9]  = -16'sd81;
        bias[m][10] =  16'sd27;
        bias[m][11] = -16'sd65;
        bias[m][12] = -16'sd68;
        bias[m][13] =  16'sd18;
        bias[m][14] =  16'sd19;
        bias[m][15] = -16'sd42;    
    end
             
    // GENERATE SCALE
    scaling_factor = 5'd8;

end endtask

task input_conv3_param_tile1_task; begin
    @(negedge clk);
    weight_idx = 0;
    instruction_valid = 1'b1;
    instruction = pack_instruction(memory_op(weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0), '0);
        // don't change mode, load weight, don't load bias and scale

    for(m=0; m<16; m=m+1) begin      // 16 pages of weights
        for(i=0; i<9; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                SRAM_weight_data[i][j] = weight[i][j][m];
            end
        end
        @(negedge clk);
        weight_idx = weight_idx + 1;
        instruction = pack_instruction(memory_op(weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0), '0);
        // don't change mode, load weight, don't load bias and scale
    end

    instruction_valid = 1'b0;
    instruction = '0;
    weight_idx = 0;
    
    @(negedge clk);
    instruction_valid = 1'b1;
    instruction = pack_instruction(memory_op(5'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0), '0);  
        // don't change mode, don't load weight, load bias and scale

    for(m=0; m<4; m=m+1) begin
        for(j=0; j<8; j=j+1) begin
            SRAM_bias_data[m][j] = bias[m][j];
        end
    end

    SRAM_scaling_factor = scaling_factor;

    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = '0;
end endtask

task input_conv3_param_tile2_task; begin
    @(negedge clk);
    weight_idx = 0;
    instruction_valid = 1'b1;
    instruction = pack_instruction(memory_op(weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0), '0);
        // don't change mode, load weight, don't load bias and scale

    for(m=0; m<16; m=m+1) begin      // 16 pages of weights
        for(i=0; i<9; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                SRAM_weight_data[i][j] = weight[i][j+8][m];
            end
        end
        @(negedge clk);
        weight_idx = weight_idx + 1;
        instruction = pack_instruction(memory_op(weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0), '0);
            // don't change mode, load weight, don't load bias and scale
    end

    instruction_valid = 1'b0;
    instruction = '0;
    weight_idx = 0;
    
    @(negedge clk);
    instruction_valid = 1'b1;
    instruction = pack_instruction(memory_op(5'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0), '0);  
        // don't change mode, don't load weight, load bias and scale

    for(m=0; m<4; m=m+1) begin
        for(j=0; j<8; j=j+1) begin
            SRAM_bias_data[m][j] = bias[m][j+8];
        end
    end

    SRAM_scaling_factor = scaling_factor;

    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = '0;
end endtask

task input_conv3_activation_task; begin
    @(negedge clk);
    instruction_valid = 1'b1;
    instruction = pack_instruction(memory_op(5'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0), compute_op(3'b0, 5'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0));
        // Dont't compute, Don't store, No ReLU, No Pool, Load Activation

    // GENERATE ACTIVATION
    for(m=0; m<8; m=m+1) begin 
        SRAM_activation[0][0][m] = image[0][0][m];
        SRAM_activation[0][1][m] = image[0][1][m];
        SRAM_activation[0][2][m] = image[0][2][m];
        SRAM_activation[0][3][m] = image[0][3][m];

        SRAM_activation[1][0][m] = image[1][0][m];
        SRAM_activation[1][1][m] = image[1][1][m];
        SRAM_activation[1][2][m] = image[1][2][m];
        SRAM_activation[1][3][m] = image[1][3][m];

        SRAM_activation[2][0][m] = image[2][0][m];
        SRAM_activation[2][1][m] = image[2][1][m];
        SRAM_activation[2][2][m] = image[2][2][m];
        SRAM_activation[2][3][m] = image[2][3][m];

        SRAM_activation[3][0][m] = image[3][0][m];
        SRAM_activation[3][1][m] = image[3][1][m];
        SRAM_activation[3][2][m] = image[3][2][m];
        SRAM_activation[3][3][m] = image[3][3][m];
    end

    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = '0;
end endtask

task input_conv3_task; begin
    for(m=0; m<16; m=m+1) begin     // 16 input channels
        instruction_valid = 1'b1;
        activation_channel = m;
        weight_idx = m;

        if(m==15) begin     // input first 8 channels of next pixel
            if((i_pixel == 1) && (j_pixel == 1)) begin      // last pixel
                instruction = pack_instruction('0, compute_op(activation_channel, weight_idx, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0));
                    // Compute, Store, ReLU, Pool, Don't Load Activation
            end
            else begin
                instruction = pack_instruction(memory_op(5'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0), compute_op(activation_channel, weight_idx, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0));
                    // Compute, Store, ReLU, Pool, Load Activation

                // GENERATE ACTIVATION
                if(j_pixel == 1) begin
                    i_next = i_pixel + 1;
                    j_next = 0;
                end
                else begin
                    i_next = i_pixel;
                    j_next = j_pixel + 1;
                end

                for(j=0; j<8; j=j+1) begin 
                    SRAM_activation[0][0][j] = image[i_next*2 + 0][j_next*2 + 0][j];
                    SRAM_activation[0][1][j] = image[i_next*2 + 0][j_next*2 + 1][j];
                    SRAM_activation[0][2][j] = image[i_next*2 + 0][j_next*2 + 2][j];
                    SRAM_activation[0][3][j] = image[i_next*2 + 0][j_next*2 + 3][j];

                    SRAM_activation[1][0][j] = image[i_next*2 + 1][j_next*2 + 0][j];
                    SRAM_activation[1][1][j] = image[i_next*2 + 1][j_next*2 + 1][j];
                    SRAM_activation[1][2][j] = image[i_next*2 + 1][j_next*2 + 2][j];
                    SRAM_activation[1][3][j] = image[i_next*2 + 1][j_next*2 + 3][j];

                    SRAM_activation[2][0][j] = image[i_next*2 + 2][j_next*2 + 0][j];
                    SRAM_activation[2][1][j] = image[i_next*2 + 2][j_next*2 + 1][j];
                    SRAM_activation[2][2][j] = image[i_next*2 + 2][j_next*2 + 2][j];
                    SRAM_activation[2][3][j] = image[i_next*2 + 2][j_next*2 + 3][j];

                    SRAM_activation[3][0][j] = image[i_next*2 + 3][j_next*2 + 0][j];
                    SRAM_activation[3][1][j] = image[i_next*2 + 3][j_next*2 + 1][j];
                    SRAM_activation[3][2][j] = image[i_next*2 + 3][j_next*2 + 2][j];
                    SRAM_activation[3][3][j] = image[i_next*2 + 3][j_next*2 + 3][j];
                end
            end
        end
        else if(m==7) begin     // Load next 8 input channels
            instruction = pack_instruction(memory_op(5'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0), compute_op(activation_channel, weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0));
                // Compute, Don't Store, No ReLU, No Pool, Load Activation

            // GENERATE ACTIVATION
            for(j=0; j<8; j=j+1) begin 
                SRAM_activation[0][0][j] = image[i_pixel*2 + 0][j_pixel*2 + 0][j+8];
                SRAM_activation[0][1][j] = image[i_pixel*2 + 0][j_pixel*2 + 1][j+8];
                SRAM_activation[0][2][j] = image[i_pixel*2 + 0][j_pixel*2 + 2][j+8];
                SRAM_activation[0][3][j] = image[i_pixel*2 + 0][j_pixel*2 + 3][j+8];

                SRAM_activation[1][0][j] = image[i_pixel*2 + 1][j_pixel*2 + 0][j+8];
                SRAM_activation[1][1][j] = image[i_pixel*2 + 1][j_pixel*2 + 1][j+8];
                SRAM_activation[1][2][j] = image[i_pixel*2 + 1][j_pixel*2 + 2][j+8];
                SRAM_activation[1][3][j] = image[i_pixel*2 + 1][j_pixel*2 + 3][j+8];

                SRAM_activation[2][0][j] = image[i_pixel*2 + 2][j_pixel*2 + 0][j+8];
                SRAM_activation[2][1][j] = image[i_pixel*2 + 2][j_pixel*2 + 1][j+8];
                SRAM_activation[2][2][j] = image[i_pixel*2 + 2][j_pixel*2 + 2][j+8];
                SRAM_activation[2][3][j] = image[i_pixel*2 + 2][j_pixel*2 + 3][j+8];

                SRAM_activation[3][0][j] = image[i_pixel*2 + 3][j_pixel*2 + 0][j+8];
                SRAM_activation[3][1][j] = image[i_pixel*2 + 3][j_pixel*2 + 1][j+8];
                SRAM_activation[3][2][j] = image[i_pixel*2 + 3][j_pixel*2 + 2][j+8];
                SRAM_activation[3][3][j] = image[i_pixel*2 + 3][j_pixel*2 + 3][j+8];
            end
        end
        else begin
            instruction = pack_instruction('0, compute_op(activation_channel, weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0));
                // Compute, Don't Store, No ReLU, No Pool, Don't Load Activation
        end
        @(negedge clk);
        instruction_valid = 1'b0;
        instruction = '0;
    end
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

task check_conv_ans_tile1_task; begin
    latency_out = 0;
    if(write_valid == 1'b1) begin
        write_word_tile1[i_out][j_out] = write_data;
        $display("************************************************************");  
        $display("                        SRAM Write!                        ");
        $display(" Received Word:  = %h", write_word_tile1[i_out][j_out]);         
        $display("************************************************************");
        @(negedge clk); 
        latency_out = latency_out + 1;
    end
    total_latency = total_latency + latency_wait + latency_out;
end endtask

task check_conv_ans_tile2_task; begin
    latency_out = 0;
    if(write_valid == 1'b1) begin
        write_word_tile2[i_out][j_out] = write_data;
        $display("************************************************************");  
        $display("                        SRAM Write!                        ");
        $display(" Received Word:  = %h", write_word_tile2[i_out][j_out]);         
        $display("************************************************************");
        @(negedge clk); 
        latency_out = latency_out + 1;
    end
    total_latency = total_latency + latency_wait + latency_out;
end endtask

task YOU_PASS_task; begin    
    // Open file for writing
    outfile = $fopen("CONV3_Tile1_OF_Map.txt", "w");
    if (outfile == 0) begin
        $display("Error: Cannot open output file.");
        $finish;
    end

    // Write 6x6 output feature map as 64-bit hex
    for (i_out = 0; i_out < 2; i_out = i_out + 1) begin
        for (j_out = 0; j_out < 2; j_out = j_out + 1) begin
            $fwrite(outfile, "%016h ", write_word_tile1[i_out][j_out]);  // space-separated
        end
        $fwrite(outfile, "\n");  // new line after each row
    end

    $fclose(outfile);
    $display("Output feature map written to CONV2_Tile1_OF_Map.txt");

    // Open file for writing
    outfile = $fopen("CONV3_Tile2_OF_Map.txt", "w");
    if (outfile == 0) begin
        $display("Error: Cannot open output file.");
        $finish;
    end

    // Write 6x6 output feature map as 64-bit hex
    for (i_out = 0; i_out < 2; i_out = i_out + 1) begin
        for (j_out = 0; j_out < 2; j_out = j_out + 1) begin
            $fwrite(outfile, "%016h ", write_word_tile2[i_out][j_out]);  // space-separated
        end
        $fwrite(outfile, "\n");  // new line after each row
    end

    $fclose(outfile);
    $display("Output feature map written to CONV2_Tile2_OF_Map.txt");

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