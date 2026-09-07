`define CYCLE_TIME 2.0 // Cycle time in nanoseconds
`define PAT_NUM 3    // Number of patterns
`define MAX_LATENCY 10000 // Max latency for each pattern
`define OUT_NUM 1       // The number of output for each pattern
`define SEED 5487
`include "Accelerator.sv"

module tb_CONV1;

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


parameter IN_ROWS = 28;
parameter IN_COLS = 28;
parameter PAD_ROWS = 30;
parameter PAD_COLS = 30;

integer status;
integer outfile;
integer file, r, row, col;
integer temp;

// ISA
//---------------------------------------------------------------------
//   REG & WIRE DECLARATION
//---------------------------------------------------------------------

reg signed [7:0] padded_image [0:PAD_ROWS-1][0:PAD_COLS-1]; // Padded image
string line;
integer temp_data [0:IN_COLS-1];

reg signed [15:0] bias [0:3][0:7];
reg [4:0] scaling_factor;
reg signed [7:0] weight [0:8][0:7];  // [row][col]

reg [4:0] weight_idx;
reg [2:0] activation_channel;

reg [63:0] write_word [0:13][0:13];

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
        $fsdbDumpfile("CONV1.fsdb");
        $fsdbDumpvars(0,"+mda");
    `endif
    `ifdef GATE
        $sdf_annotate("./Netlist/Accelerator_SYN.sdf");
        $fsdbDumpfile("CONV1_SYN.fsdb");
        $fsdbDumpvars(0,"+mda"); 
    `endif
end

initial begin
    reset_task;
    repeat (2) @(negedge clk);
    // for(i_pat = 0; i_pat < patnum; i_pat = i_pat + 1) begin
        
    // end 

    instruction_valid = 1'b1;
    instruction = pack_instruction(memory_op(5'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0), '0);  // change mode to Conv, don't load weight, don't load bias and scale
    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = '0;

    i_pat = 0;
    read_image_task;
    generate_conv1_param_task;
    input_conv1_param_task;

    input_conv1_activation_task;
    for(i_pixel = 0; i_pixel < 14; i_pixel = i_pixel + 1) begin
        for(j_pixel = 0; j_pixel < 14; j_pixel = j_pixel + 1) begin
            input_conv1_task;
        end
    end

    repeat(18) @(negedge clk);
end

initial begin
    // for ( j_pat = 0 ; j_pat < patnum; j_pat = j_pat + 1) begin
        
    // end
    j_pat = 0;
    $display("************************************************************");  
    $display("                        Conv1 Layer                         ");
    $display("     INPUT: 1 Image * 28 * 28 Pixels (Padded to 30 * 30)    ");
    $display("     OUTPUT: 8 OFMAPS * 14 * 14 Pixels (ReLU + Pooled)      ");         
    $display("************************************************************");

    for(i_out = 0; i_out < 14; i_out = i_out + 1) begin
        for(j_out = 0; j_out < 14; j_out = j_out + 1) begin
            wait_begin_check_task;
            check_conv_ans_task;
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
    file = $fopen("image.txt", "r");
    if (file == 0) begin
        $display("Error: Failed to open image.txt");
        $finish;
    end
    // Zero all pixels first
    for (i = 0; i < PAD_ROWS; i = i + 1)
        for (j = 0; j < PAD_COLS; j = j + 1)
            padded_image[i][j] = 8'd0;
    // Load 28×28 image into center of 30×30 array
    for (i = 0; i < IN_ROWS; i = i + 1) begin
        if (!$feof(file)) begin
            status = $fgets(line, file);
            if (status != 0) begin
                status = $sscanf(line,
                    "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
                    temp_data[0], temp_data[1], temp_data[2], temp_data[3],
                    temp_data[4], temp_data[5], temp_data[6], temp_data[7],
                    temp_data[8], temp_data[9], temp_data[10], temp_data[11],
                    temp_data[12], temp_data[13], temp_data[14], temp_data[15],
                    temp_data[16], temp_data[17], temp_data[18], temp_data[19],
                    temp_data[20], temp_data[21], temp_data[22], temp_data[23],
                    temp_data[24], temp_data[25], temp_data[26], temp_data[27]
                );
                if (status == IN_COLS) begin
                    for (j = 0; j < IN_COLS; j = j + 1)
                        padded_image[i + 1][j + 1] = temp_data[j][7:0];
                end else begin
                    $fatal(1, "Error parsing row %0d", i);
                end
            end
        end
    end
    $fclose(file);
    // Display padded image (optional)
    $display("Padded 30x30 Image:");
    for (i = 0; i < PAD_ROWS; i = i + 1) begin
        for (j = 0; j < PAD_COLS; j = j + 1) begin
            $write("%3d ", padded_image[i][j]);
        end
        $write("\n");
    end
end endtask


// Conv1 Task
task generate_conv1_param_task; begin
    // GENERATE WEIGHT
    file = $fopen("conv1_weights_tb.txt", "r");
    if (file == 0) begin
      $display("Failed to open file!");
      $finish;
    end

    for (row = 0; row < 9; row = row + 1) begin
      for (col = 0; col < 8; col = col + 1) begin
        r = $fscanf(file, "%d", temp);
        weight[row][col] = temp;
      end
    end

    $fclose(file);

    // // Print to check
    // for (row = 0; row < 9; row = row + 1) begin
    //   for (col = 0; col < 8; col = col + 1) begin
    //     $display("weight[%0d][%0d] = %0d", row, col, weight[row][col]);
    //   end
    // end

    // GENERATE BIAS
    for(m=0; m<4; m=m+1) begin
        bias[m][0] =  16'sd163;
        bias[m][1] = -16'sd555;
        bias[m][2] =  16'sd565;
        bias[m][3] =  16'sd481;
        bias[m][4] =  16'sd565;
        bias[m][5] =  16'sd1134;
        bias[m][6] =  16'sd1787;
        bias[m][7] =  16'sd1359;
    end
             
    // GENERATE SCALE
    scaling_factor = 5'd12;

end endtask

task input_conv1_param_task; begin
    @(negedge clk);
    weight_idx = 0;
    instruction_valid = 1'b1;
    instruction = pack_instruction(memory_op(weight_idx, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0), '0);
        // don't change mode, load weight, don't load bias and scale

    for(i=0; i<9; i=i+1) begin
        for(j=0; j<8; j=j+1) begin
            SRAM_weight_data[i][j] = weight[i][j];
        end
    end
    
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

task input_conv1_activation_task; begin
    @(negedge clk);
    instruction_valid = 1'b1;
    instruction = pack_instruction(memory_op(5'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0), compute_op(3'b0, 5'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0));
        // Dont't compute, Don't store, No ReLU, No Pool, Load Activation

    // GENERATE ACTIVATION
    for(m=0; m<1; m=m+1) begin 
        SRAM_activation[0][0][m] = padded_image[0][0];
        SRAM_activation[0][1][m] = padded_image[0][1];
        SRAM_activation[0][2][m] = padded_image[0][2];
        SRAM_activation[0][3][m] = padded_image[0][3];

        SRAM_activation[1][0][m] = padded_image[1][0];
        SRAM_activation[1][1][m] = padded_image[1][1];
        SRAM_activation[1][2][m] = padded_image[1][2];
        SRAM_activation[1][3][m] = padded_image[1][3];

        SRAM_activation[2][0][m] = padded_image[2][0];
        SRAM_activation[2][1][m] = padded_image[2][1];
        SRAM_activation[2][2][m] = padded_image[2][2];
        SRAM_activation[2][3][m] = padded_image[2][3];

        SRAM_activation[3][0][m] = padded_image[3][0];
        SRAM_activation[3][1][m] = padded_image[3][1];
        SRAM_activation[3][2][m] = padded_image[3][2];
        SRAM_activation[3][3][m] = padded_image[3][3];
    end
    for(m=1; m<8; m=m+1) begin 
        for(i=0; i<4; i=i+1) begin
            for(j=0; j<4; j=j+1) begin
                SRAM_activation[i][j][m] = 0;
            end 
        end
    end
    @(negedge clk);
    instruction_valid = 1'b0;
    instruction = '0;
end endtask

task input_conv1_task; begin
    for(m=0; m<1; m=m+1) begin
        instruction_valid = 1'b1;
        activation_channel = m;
        weight_idx = m;

        if((i_pixel == 13) && (j_pixel == 13)) begin
            instruction = pack_instruction('0, compute_op(activation_channel, weight_idx, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0));
                // Compute, Store, ReLU, Pool, Don't Load Activation
        end
        else begin
            instruction = pack_instruction(memory_op(5'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0), compute_op(activation_channel, weight_idx, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0));
                // Compute, Store, ReLU, Pool, Load Activation

            // GENERATE ACTIVATION
            if(j_pixel == 13) begin
                i_next = i_pixel + 1;
                j_next = 0;
            end
            else begin
                i_next = i_pixel;
                j_next = j_pixel + 1;
            end

            for(m=0; m<1; m=m+1) begin 
                SRAM_activation[0][0][m] = padded_image[i_next*2 + 0][j_next*2 + 0];
                SRAM_activation[0][1][m] = padded_image[i_next*2 + 0][j_next*2 + 1];
                SRAM_activation[0][2][m] = padded_image[i_next*2 + 0][j_next*2 + 2];
                SRAM_activation[0][3][m] = padded_image[i_next*2 + 0][j_next*2 + 3];

                SRAM_activation[1][0][m] = padded_image[i_next*2 + 1][j_next*2 + 0];
                SRAM_activation[1][1][m] = padded_image[i_next*2 + 1][j_next*2 + 1];
                SRAM_activation[1][2][m] = padded_image[i_next*2 + 1][j_next*2 + 2];
                SRAM_activation[1][3][m] = padded_image[i_next*2 + 1][j_next*2 + 3];

                SRAM_activation[2][0][m] = padded_image[i_next*2 + 2][j_next*2 + 0];
                SRAM_activation[2][1][m] = padded_image[i_next*2 + 2][j_next*2 + 1];
                SRAM_activation[2][2][m] = padded_image[i_next*2 + 2][j_next*2 + 2];
                SRAM_activation[2][3][m] = padded_image[i_next*2 + 2][j_next*2 + 3];

                SRAM_activation[3][0][m] = padded_image[i_next*2 + 3][j_next*2 + 0];
                SRAM_activation[3][1][m] = padded_image[i_next*2 + 3][j_next*2 + 1];
                SRAM_activation[3][2][m] = padded_image[i_next*2 + 3][j_next*2 + 2];
                SRAM_activation[3][3][m] = padded_image[i_next*2 + 3][j_next*2 + 3];
            end
            for(m=1; m<8; m=m+1) begin 
                for(i=0; i<4; i=i+1) begin
                    for(j=0; j<4; j=j+1) begin
                        SRAM_activation[i][j][m] = 0;
                    end 
                end
            end
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

task check_conv_ans_task; begin
    latency_out = 0;
    if(write_valid == 1'b1) begin
        write_word[i_out][j_out] = write_data;
        $display("************************************************************");  
        $display("                        SRAM Write!                        ");
        $display(" Received Word:  = %h", write_word[i_out][j_out]);         
        $display("************************************************************");
        @(negedge clk); 
        latency_out = latency_out + 1;
    end
    total_latency = total_latency + latency_wait + latency_out;
end endtask

task YOU_PASS_task; begin    
    // Open file for writing
    outfile = $fopen("CONV1_OF_Map.txt", "w");
    if (outfile == 0) begin
        $display("Error: Cannot open output file.");
        $finish;
    end

    // Write 14x14 output feature map as 64-bit hex
    for (i_out = 0; i_out < 14; i_out = i_out + 1) begin
        for (j_out = 0; j_out < 14; j_out = j_out + 1) begin
            $fwrite(outfile, "%016h ", write_word[i_out][j_out]);  // space-separated
        end
        $fwrite(outfile, "\n");  // new line after each row
    end

    $fclose(outfile);
    $display("Output feature map written to CONV1_OF_Map.txt");

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