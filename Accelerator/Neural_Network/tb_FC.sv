`define CYCLE_TIME 2.0 // Cycle time in nanoseconds
`define PAT_NUM 3    // Number of patterns
`define MAX_LATENCY 10000 // Max latency for each pattern
`define OUT_NUM 1       // The number of output for each pattern
`define SEED 5487
`include "../Accelerator/Accelerator.sv"

module tb_FC;

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
integer i_pixel, j_pixel;
integer i_out, j_out;
integer weight_count;
integer i_flatten;


parameter IN_ROWS = 2;
parameter IN_COLS = 2;

integer status;
integer outfile;
integer file, row, col, page, r, temp;

// ISA
parameter NO_OP = 3'b000;                      // No operation
parameter LOAD = 3'b001;                // Change operation modes Conv or Fully Connect
         // {mode[15:13], Change Mode[12], Operation Mode[11], Load Weight[10], Weight idx[9:5], Load Param[4], 4'b0}    // 0 = Conv, 1 = FC
parameter MAC_COMPUTE = 3'b010;                
         // {mode[15:13], Activation Channel[12:10], Weight idx[9:5], MAC[4], Store[3], ReLU[2], Pool[1], Load Activation[0]}
//---------------------------------------------------------------------
//   REG & WIRE DECLARATION
//---------------------------------------------------------------------

reg signed [7:0] image [0:IN_ROWS-1][0:IN_COLS-1][0:15]; // Padded image
reg [64*256-1:0] line;
reg [63:0] temp_data [0:IN_COLS-1];
reg signed [7:0] array [0:71];

reg signed [7:0] weight [0:8][0:9][0:7];    // INT8, 9 weights, 10 output features, 8 pages of weights
reg signed [15:0] bias [0:3][0:7];
reg [4:0] scaling_factor;

reg [4:0] weight_idx;
reg [2:0] activation_channel;

reg [63:0] write_word [0:3];
reg signed [7:0] output_pixel [0:9];

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
        $fsdbDumpfile("FC.fsdb");
        $fsdbDumpvars(0,"+mda");
    `endif
    `ifdef GATE
        $sdf_annotate("./Netlist/Accelerator_SYN.sdf");
        $fsdbDumpfile("FC_SYN.fsdb");
        $fsdbDumpvars(0,"+mda"); 
    `endif
end

initial begin
    reset_task;
    repeat (2) @(negedge clk);
    // for(i_pat = 0; i_pat < patnum; i_pat = i_pat + 1) begin
        
    // end 

    instruction_valid = 1'b1;
    instruction = {LOAD, 3'b0, 5'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0};  
        // change mode to FC, don't load weight, don't load bias and scale
    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};

    i_pat = 0;
    @(negedge clk);
    read_image_task;
    generate_fc_param_task;
    input_fc_param_task;
    
    input_fc_activation_task;
    input_fc_task;

    repeat(18) @(negedge clk);
end

initial begin
    // for ( j_pat = 0 ; j_pat < patnum; j_pat = j_pat + 1) begin
        
    // end
    j_pat = 0;
    $display("************************************************************");  
    $display("                           FC Layer                         ");
    $display("     INPUT:   16 IFMAPS * 2 * 2 Pixels (Flattened)          ");
    $display("     OUTPUT:      10 Output Features                        ");         
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
   
task read_image_task; begin
    // Zero all pixels first (optional)
    for (i = 0; i < IN_ROWS; i = i + 1)
        for (j = 0; j < IN_COLS; j = j + 1)
            for (m = 0; m < 16; m = m + 1)
                image[i][j][m] = 8'd0;
    
    // First Image
    file = $fopen("CONV3_Tile1_OF_Map.txt", "r");
    if (file == 0) begin
        $display("Error: Failed to open CONV3_Tile1_OF_Map.txt");
        $finish;
    end

    // Load 2×2 image directly (no +1 offsets)
    for (i = 0; i < IN_ROWS; i = i + 1) begin
        if (!$feof(file)) begin
            status = $fgets(line, file);
            if (status != 0) begin
                status = $sscanf(line,
                    "%016h %016h",
                    temp_data[0], temp_data[1]);
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
                    $display("Error parsing row %0d", i);
                end
            end
        end
    end

    $fclose(file);

    // Second Image
    file = $fopen("CONV3_Tile2_OF_Map.txt", "r");
    if (file == 0) begin
        $display("Error: Failed to open CONV3_Tile2_OF_Map.txt");
        $finish;
    end

    // Load 2×2 image directly (no +1 offsets)
    for (i = 0; i < IN_ROWS; i = i + 1) begin
        if (!$feof(file)) begin
            status = $fgets(line, file);
            if (status != 0) begin
                status = $sscanf(line,
                    "%016h %016h",
                    temp_data[0], temp_data[1]);
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
                    $display("Error parsing row %0d", i);
                end
            end
        end
    end

    $fclose(file);

    // Flatten
    for(i_flatten = 0; i_flatten < 72; i_flatten = i_flatten + 1) begin
        array[i_flatten] = 0;
    end

    i_flatten = 0;
    for (m = 0; m < 16; m = m + 1) begin
        for (i = 0; i < IN_ROWS; i = i + 1) begin
            for (j = 0; j < IN_COLS; j = j + 1) begin
                array[i_flatten] = image[i][j][m];
                i_flatten = i_flatten + 1;
            end
        end
    end

end endtask


// FC Task
task generate_fc_param_task; begin
    // GENERATE WEIGHT
    file = $fopen("fc_weights_tb.txt", "r");
    if (file == 0) begin
      $display("Failed to open file!");
      $finish;
    end

    weight_count = 0;
    for (page = 0; page < 8; page = page + 1) begin
      for (row = 0; row < 9; row = row + 1) begin
        for (col = 0; col < 10; col = col + 1) begin
          r = $fscanf(file, "%d", temp);
          if(weight_count > 63) weight[row][col][page] = 0;
          else weight[row][col][page] = temp;
        end
        weight_count = weight_count + 1;
      end
    end
    $fclose(file);

    // for (col = 0; col < 10; col = col + 1) begin
    //     for (page = 0; page < 8; page = page + 1) begin
    //         for (row = 0; row < 9; row = row + 1) begin        
    //             $display("weight[%0d][%0d][%0d] = %0d", row, col, page, weight[row][col][page]);
    //         end
    //     end
    // end

    // GENERATE BIAS
    for(m=0; m<4; m=m+1) begin
        for(j=0; j<8; j=j+1) begin
            bias[m][j] = 16'b0;
        end
    end

    bias[0][0]  =  16'sd108;
    bias[0][1]  =  16'sd186;
    bias[0][2]  = -16'sd19;
    bias[0][3]  = -16'sd68;
    bias[0][4]  =  16'sd90;
    bias[0][5]  =  16'sd140;
    bias[0][6]  =  16'sd69;
    bias[0][7]  = -16'sd140;
    bias[1][0]  = -16'sd31;
    bias[1][1]  =  16'sd71;
 
    
    // GENERATE SCALE
    scaling_factor = 5'd5;

end endtask

task input_fc_param_task; begin
    @(negedge clk);
    weight_idx = 0;
    instruction_valid = 1'b1;
    instruction = {LOAD, 3'b0, weight_idx, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0};
        // don't change mode, load weight, don't load bias and scale

    for(m=0; m<8; m=m+1) begin      // 8 pages of weights for Core 1
        for(i=0; i<9; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                SRAM_weight_data[i][j] = weight[i][j][m];
            end
        end
        @(negedge clk);
        weight_idx = weight_idx + 1;
        instruction = {LOAD, 3'b0, weight_idx, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0};
        // don't change mode, load weight, don't load bias and scale
    end

    weight_idx = 8;
    instruction = {LOAD, 3'b0, weight_idx, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0};
        // don't change mode, load weight, don't load bias and scale

    for(m=0; m<8; m=m+1) begin      // 8 pages of weights for Core 2
        for(i=0; i<9; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                if(j > 1) SRAM_weight_data[i][j] = 0;
                else SRAM_weight_data[i][j] = weight[i][j+8][m];
            end
        end
        @(negedge clk);
        weight_idx = weight_idx + 1;
        instruction = {LOAD, 3'b0, weight_idx, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0};
        // don't change mode, load weight, don't load bias and scale
    end

    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};
    weight_idx = 0;
    
    @(negedge clk);
    instruction_valid = 1'b1;
    instruction = {LOAD, 3'b0, 5'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1};  
        // don't change mode, don't load weight, load bias and scale

    for(m=0; m<4; m=m+1) begin
        for(j=0; j<8; j=j+1) begin
            SRAM_bias_data[m][j] = bias[m][j];
        end
    end

    SRAM_scaling_factor = scaling_factor;

    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};
end endtask

task input_fc_activation_task; begin
    @(negedge clk);
    instruction_valid = 1'b1;
    instruction = {MAC_COMPUTE, 3'b0, 5'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1};
        // Dont't compute, Don't store, No ReLU, No Pool, Load Activation

    // GENERATE ACTIVATION
    for(m=0; m<8; m=m+1) begin 
        SRAM_activation[0][0][m] = array[m*9 + 0];
        SRAM_activation[0][1][m] = array[m*9 + 1];
        SRAM_activation[0][2][m] = array[m*9 + 2];
        SRAM_activation[0][3][m] = 0;

        SRAM_activation[1][0][m] = array[m*9 + 3];
        SRAM_activation[1][1][m] = array[m*9 + 4];
        SRAM_activation[1][2][m] = array[m*9 + 5];
        SRAM_activation[1][3][m] = 0;

        SRAM_activation[2][0][m] = array[m*9 + 6];
        SRAM_activation[2][1][m] = array[m*9 + 7];
        SRAM_activation[2][2][m] = array[m*9 + 8];
        SRAM_activation[2][3][m] = 0;

        SRAM_activation[3][0][m] = 0;
        SRAM_activation[3][1][m] = 0;
        SRAM_activation[3][2][m] = 0;
        SRAM_activation[3][3][m] = 0;
    end

    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};
end endtask

task input_fc_task; begin
    for(m=0; m<7; m=m+1) begin
        instruction_valid = 1'b1;
        activation_channel = m;
        weight_idx = m;
        instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0};
                // Compute, Don't Store, No ReLU, No Pool, Don't Load Activation
        @(negedge clk);
    end

    instruction_valid = 1'b1;
    activation_channel = 3'd7;
    weight_idx = 5'd7;
    instruction = {MAC_COMPUTE, activation_channel, weight_idx, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0};
                // Compute, Store, No ReLU, No Pool, Don't Load Activation

    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = {NO_OP, 13'b0};
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

task check_fc_ans_task; begin
    latency_out = 0;
    if(write_valid == 1'b1) begin
        for(j_out=0; j_out<4; j_out=j_out+1) begin
            write_word[j_out] = write_data;
            $display("************************************************************");  
            $display("                        SRAM Write!                        ");
            $display(" Received Word:  = %h", write_word[j_out]);         
            $display("************************************************************");
            @(negedge clk);
            latency_out = latency_out + 1;
        end
    end

    output_pixel[0] = write_word[0][63:56];
    output_pixel[1] = write_word[0][55:48];
    output_pixel[2] = write_word[0][47:40];
    output_pixel[3] = write_word[0][39:32];
    output_pixel[4] = write_word[0][31:24];
    output_pixel[5] = write_word[0][23:16];
    output_pixel[6] = write_word[0][15:8];
    output_pixel[7] = write_word[0][7:0];
    output_pixel[8] = write_word[1][63:56];
    output_pixel[9] = write_word[1][55:48];
    
    for(j_out=0; j_out<10; j_out=j_out+1) begin
        $display("************************************************************");  
        $display("                       End of Case!                        ");
        $display(" Output Feature No.:  = %d", j_out);                                      
        $display(" Received:  = %d", output_pixel[j_out]);         
        $display("************************************************************");
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