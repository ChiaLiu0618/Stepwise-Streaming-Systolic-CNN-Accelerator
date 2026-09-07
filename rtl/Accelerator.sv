`include "regfiles.sv"
`include "Controller.sv"
`include "Triangle_Buffer.sv"
`include "Systolic_Array.sv"
module Accelerator (
            input clk, rst_n,
            input instruction_valid, input Instructions::instruction_t instruction,
        
            input signed [7:0] SRAM_activation [0:3][0:3][0:7],
            input signed [7:0] SRAM_weight_data [0:8][0:7],     // a page of weights to load regfile
            input signed [15:0] SRAM_bias_data [0:3][0:7],      // 32 bias
            input [4:0] SRAM_scaling_factor,
            
            output reg write_valid, output reg [63:0] write_data
            );
                
integer i, j, m;

wire mode;
wire load_bias;
wire load_scale;
wire load_weight;              // load new weights
wire [4:0] weight_idx;         // index to load regfile
wire load_activation_bank;
wire activation_bank;

reg signed [7:0] activation_window [0:1][0:3][0:3][0:7];     // Two INT8 windows: independent load and compute banks
reg [2:0] activation_channel;      // 0~7 activation windows for different input channels
wire load_activation;

reg signed [15:0] bias [0:3][0:7];
reg [4:0] scaling_factor;

reg signed [7:0] weight_data [0:3][0:8][0:7];   // INT8, 4 arrays, 9 by 8 PEs
wire [4:0] weight_set [0:15];      // 0~31 weight sets for 16 propagates

reg signed [7:0] input_data [0:3][0:8];
wire input_valid;

wire signed [7:0] padded_input_data [0:3][0:8];
wire padded_input_valid [0:3][0:8];

wire sum_valid [0:3][0:7];
wire signed [31:0] sum_out [0:3][0:7];

reg signed [31:0] accu_sum [0:3][0:7];
wire MAC_end [0:7];

reg signed [31:0] ReLU_pixel [0:3][0:7];
wire ReLU [0:7];

reg signed [7:0] quantized_pixel [0:3][0:7];
reg quant_valid [0:3][0:7];
reg signed [31:0] scaled_pixel [0:3][0:7];

reg signed [7:0] output_pixel [0:3][0:7];
reg output_valid [0:3][0:7];

reg signed [7:0] MAX_temp [0:7][0:1];
reg signed [7:0] MAX_pixel [0:7];
wire Pool;

reg [1:0] write_counter;

// Controller
Controller C1 (.clk(clk), .rst_n(rst_n),
                .instruction_valid(instruction_valid), .instruction(instruction),
                
                .mode(mode),
                .load_bias(load_bias),
                .load_scale(load_scale),
                .load_weight(load_weight),
                .weight_idx(weight_idx),
                .load_activation(load_activation),
                .load_activation_bank(load_activation_bank),
                .activation_bank(activation_bank),

                .input_valid(input_valid),
                .activation_channel(activation_channel),
                .weight_set(weight_set),
                .MAC_end(MAC_end), .ReLU(ReLU), .Pool(Pool)
                );

// Compute captures the selected old window at the edge; a load updates its
// destination after the edge. Use the other bank to prefetch multiple cycles ahead.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (int bank = 0; bank < 2; bank++)
            for (int row = 0; row < 4; row++)
                for (int col = 0; col < 4; col++)
                    for (int channel = 0; channel < 8; channel++)
                        activation_window[bank][row][col][channel] <= '0;
    end else if (load_activation) begin
        for (int row = 0; row < 4; row++)
            for (int col = 0; col < 4; col++)
                for (int channel = 0; channel < 8; channel++)
                    activation_window[load_activation_bank][row][col][channel]
                        <= SRAM_activation[row][col][channel];
    end
end

always @(*) begin
    if(mode) begin      // Fully Connect
        for(m=0; m<4; m=m+1) begin
            input_data[m][0] = activation_window[activation_bank][0][0][activation_channel];
            input_data[m][1] = activation_window[activation_bank][0][1][activation_channel];
            input_data[m][2] = activation_window[activation_bank][0][2][activation_channel];
            input_data[m][3] = activation_window[activation_bank][1][0][activation_channel];
            input_data[m][4] = activation_window[activation_bank][1][1][activation_channel];
            input_data[m][5] = activation_window[activation_bank][1][2][activation_channel];
            input_data[m][6] = activation_window[activation_bank][2][0][activation_channel];
            input_data[m][7] = activation_window[activation_bank][2][1][activation_channel];
            input_data[m][8] = activation_window[activation_bank][2][2][activation_channel];
        end
    end
    else begin          // Convolution
        // Core 1
        input_data[0][0] = activation_window[activation_bank][0][0][activation_channel];
        input_data[0][1] = activation_window[activation_bank][0][1][activation_channel];
        input_data[0][2] = activation_window[activation_bank][0][2][activation_channel];
        input_data[0][3] = activation_window[activation_bank][1][0][activation_channel];
        input_data[0][4] = activation_window[activation_bank][1][1][activation_channel];
        input_data[0][5] = activation_window[activation_bank][1][2][activation_channel];
        input_data[0][6] = activation_window[activation_bank][2][0][activation_channel];
        input_data[0][7] = activation_window[activation_bank][2][1][activation_channel];
        input_data[0][8] = activation_window[activation_bank][2][2][activation_channel];

        // Core 2
        input_data[1][0] = activation_window[activation_bank][0][1][activation_channel];
        input_data[1][1] = activation_window[activation_bank][0][2][activation_channel];
        input_data[1][2] = activation_window[activation_bank][0][3][activation_channel];
        input_data[1][3] = activation_window[activation_bank][1][1][activation_channel];
        input_data[1][4] = activation_window[activation_bank][1][2][activation_channel];
        input_data[1][5] = activation_window[activation_bank][1][3][activation_channel];
        input_data[1][6] = activation_window[activation_bank][2][1][activation_channel];
        input_data[1][7] = activation_window[activation_bank][2][2][activation_channel];
        input_data[1][8] = activation_window[activation_bank][2][3][activation_channel];

        // Core 3
        input_data[2][0] = activation_window[activation_bank][1][0][activation_channel];
        input_data[2][1] = activation_window[activation_bank][1][1][activation_channel];
        input_data[2][2] = activation_window[activation_bank][1][2][activation_channel];
        input_data[2][3] = activation_window[activation_bank][2][0][activation_channel];
        input_data[2][4] = activation_window[activation_bank][2][1][activation_channel];
        input_data[2][5] = activation_window[activation_bank][2][2][activation_channel];
        input_data[2][6] = activation_window[activation_bank][3][0][activation_channel];
        input_data[2][7] = activation_window[activation_bank][3][1][activation_channel];
        input_data[2][8] = activation_window[activation_bank][3][2][activation_channel];

        // Core 4
        input_data[3][0] = activation_window[activation_bank][1][1][activation_channel];
        input_data[3][1] = activation_window[activation_bank][1][2][activation_channel];
        input_data[3][2] = activation_window[activation_bank][1][3][activation_channel];
        input_data[3][3] = activation_window[activation_bank][2][1][activation_channel];
        input_data[3][4] = activation_window[activation_bank][2][2][activation_channel];
        input_data[3][5] = activation_window[activation_bank][2][3][activation_channel];
        input_data[3][6] = activation_window[activation_bank][3][1][activation_channel];
        input_data[3][7] = activation_window[activation_bank][3][2][activation_channel];
        input_data[3][8] = activation_window[activation_bank][3][3][activation_channel];
    end
end

// One 8 x 32-bit regfile per PE position, shared across all four arrays.
// Logical page {lane, entry} preserves the original 32-page load interface.
genvar weight_row, weight_col, weight_lane;
generate
    for (weight_row = 0; weight_row < 9; weight_row++) begin : weight_rows
        for (weight_col = 0; weight_col < 8; weight_col++) begin : weight_cols
            wire [31:0] packed_weights;
            Weight_Regfile weights (
                .clk(clk), .rst_n(rst_n),
                .read_addr(weight_set[weight_row+weight_col][2:0]),
                .read_data(packed_weights),
                .write_en(load_weight),
                .write_mask(4'b0001 << weight_idx[4:3]),
                .write_addr(weight_idx[2:0]),
                .write_data({4{SRAM_weight_data[weight_row][weight_col]}})
            );
            for (weight_lane = 0; weight_lane < 4; weight_lane++) begin : lanes
                // FC uses pages 0..7 plus a per-array offset of 8 pages.
                // Convolution broadcasts the selected logical page to all arrays.
                assign weight_data[weight_lane][weight_row][weight_col] = mode
                    ? packed_weights[8*weight_lane +: 8]
                    : packed_weights[8*weight_set[weight_row+weight_col][4:3] +: 8];
            end
        end
    end
endgenerate

// BIAS
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(i=0; i<4; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                bias[i][j] <= 16'b0;
            end
        end
    end
    else if(load_bias) begin
        for(i=0; i<4; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                bias[i][j] <= SRAM_bias_data[i][j];
            end
        end
    end
    else begin
        for(i=0; i<4; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                bias[i][j] <= bias[i][j];
            end
        end
    end
end

// SCALING FACTOR
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) scaling_factor <= 5'b0;
    else if(load_scale) scaling_factor <= SRAM_scaling_factor;
    else scaling_factor <= scaling_factor;
end

// Core 1
Input_Buffer I1(.clk(clk), .rst_n(rst_n), 
                   .input_valid(input_valid), .input_data(input_data[0]),
                   .padded_input_valid(padded_input_valid[0]), .padded_input_data(padded_input_data[0]));

Systolic_Array S1(.clk(clk), .rst_n(rst_n), 
                  .weight_data(weight_data[0]),
                  .padded_input_valid(padded_input_valid[0]), .padded_input_data(padded_input_data[0]),
                  .sum_valid(sum_valid[0]), .sum_out(sum_out[0]));

// Core 2
Input_Buffer I2(.clk(clk), .rst_n(rst_n), 
                   .input_valid(input_valid), .input_data(input_data[1]),
                   .padded_input_valid(padded_input_valid[1]), .padded_input_data(padded_input_data[1]));

Systolic_Array S2(.clk(clk), .rst_n(rst_n), 
                  .weight_data(weight_data[1]),
                  .padded_input_valid(padded_input_valid[1]), .padded_input_data(padded_input_data[1]),
                  .sum_valid(sum_valid[1]), .sum_out(sum_out[1]));

// Core 3
Input_Buffer I3(.clk(clk), .rst_n(rst_n), 
                   .input_valid(input_valid), .input_data(input_data[2]),
                   .padded_input_valid(padded_input_valid[2]), .padded_input_data(padded_input_data[2]));

Systolic_Array S3(.clk(clk), .rst_n(rst_n), 
                  .weight_data(weight_data[2]),
                  .padded_input_valid(padded_input_valid[2]), .padded_input_data(padded_input_data[2]),
                  .sum_valid(sum_valid[2]), .sum_out(sum_out[2]));

// Core 4
Input_Buffer I4(.clk(clk), .rst_n(rst_n), 
                   .input_valid(input_valid), .input_data(input_data[3]),
                   .padded_input_valid(padded_input_valid[3]), .padded_input_data(padded_input_data[3]));
                
Systolic_Array S4(.clk(clk), .rst_n(rst_n), 
                  .weight_data(weight_data[3]),
                  .padded_input_valid(padded_input_valid[3]), .padded_input_data(padded_input_data[3]),
                  .sum_valid(sum_valid[3]), .sum_out(sum_out[3]));

// ACCU
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(i=0; i<4; i=i+1)
            for(j=0; j<8; j=j+1)
                accu_sum[i][j] <= 32'b0;
    end
    else begin
        for(i=0; i<4; i=i+1)
            for(j=0; j<8; j=j+1) begin
                if(load_bias) accu_sum[i][j] <= SRAM_bias_data[i][j];
                else begin
                    case({sum_valid[i][j], MAC_end[j]})
                        2'b11: accu_sum[i][j] <= bias[i][j] + sum_out[i][j];
                        2'b10: accu_sum[i][j] <= accu_sum[i][j] + sum_out[i][j];   // MAC, accumulate partial sums
                        2'b01: accu_sum[i][j] <= bias[i][j];    // end of MAC, clear
                        default: accu_sum[i][j] <= accu_sum[i][j];
                    endcase
                end
            end
    end
end

// ReLU
always @(*) begin
    for(i=0; i<4; i=i+1) begin
        for(j=0; j<8; j=j+1) begin
            if(ReLU[j] && accu_sum[i][j][31]) ReLU_pixel[i][j] = 32'b0;
            else ReLU_pixel[i][j] = accu_sum[i][j];
        end
    end
end 

// QUANTIZATION
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(i=0; i<4; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                quantized_pixel[i][j] <= 8'b0;
                quant_valid[i][j] <= 1'b0;
            end
        end
    end
    else begin
        for(i=0; i<4; i=i+1) begin
            for(j=0; j<8; j=j+1) begin
                if(MAC_end[j]) begin
                    if(scaled_pixel[i][j] > 32'sd127) quantized_pixel[i][j] <= 8'sd127;
                    else if(scaled_pixel[i][j] < -32'sd128) quantized_pixel[i][j] <= -8'sd128;
                    else quantized_pixel[i][j] <= scaled_pixel[i][j][7:0];    // clamp after scaling    
                    quant_valid[i][j] <= 1'b1;
                end
                else begin
                    quantized_pixel[i][j] <= quantized_pixel[i][j];
                    quant_valid[i][j] <= 1'b0;
                end
            end
        end
    end
end

always @(*) begin
    for(i=0; i<4; i=i+1) begin
        for(j=0; j<8; j=j+1) begin
            scaled_pixel[i][j] = ReLU_pixel[i][j] >>> scaling_factor;      // Scale pixel value (signed shift)
        end
    end
end 

// ALIGNING BUFFER
Output_Buffer O1 (.clk(clk), .rst_n(rst_n), 
                    .input_valid(quant_valid[0]), .input_data(quantized_pixel[0]),
                    .padded_input_valid(output_valid[0]), .padded_input_data(output_pixel[0]));

Output_Buffer O2 (.clk(clk), .rst_n(rst_n), 
                    .input_valid(quant_valid[1]), .input_data(quantized_pixel[1]),
                    .padded_input_valid(output_valid[1]), .padded_input_data(output_pixel[1]));

Output_Buffer O3 (.clk(clk), .rst_n(rst_n), 
                    .input_valid(quant_valid[2]), .input_data(quantized_pixel[2]),
                    .padded_input_valid(output_valid[2]), .padded_input_data(output_pixel[2]));

Output_Buffer O4 (.clk(clk), .rst_n(rst_n), 
                    .input_valid(quant_valid[3]), .input_data(quantized_pixel[3]),
                    .padded_input_valid(output_valid[3]), .padded_input_data(output_pixel[3]));


// Pooling
always @(*) begin
    for(j=0; j<8; j=j+1) begin
        if(output_pixel[0][j] > output_pixel[1][j]) MAX_temp[j][0] = output_pixel[0][j];
        else MAX_temp[j][0] = output_pixel[1][j];

        if(output_pixel[2][j] > output_pixel[3][j]) MAX_temp[j][1] = output_pixel[2][j];
        else MAX_temp[j][1] = output_pixel[3][j];

        if(MAX_temp[j][0] > MAX_temp[j][1]) MAX_pixel[j] = MAX_temp[j][0];
        else MAX_pixel[j] = MAX_temp[j][1];
    end
end  

// PSEUDO SRAM
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        write_data <= 64'b0;
        write_valid <= 1'b0;
        write_counter <= 2'b0;
    end
    else if((output_valid[0][0] == 1'b1) || (write_counter !== 2'd0)) begin
        if(Pool) begin
            write_data <= {MAX_pixel[0], MAX_pixel[1], MAX_pixel[2], MAX_pixel[3],
                             MAX_pixel[4], MAX_pixel[5], MAX_pixel[6], MAX_pixel[7]};
            write_counter <= 2'b0;
        end
        else begin
            write_data <= {output_pixel[write_counter][0], output_pixel[write_counter][1],
                           output_pixel[write_counter][2], output_pixel[write_counter][3],
                           output_pixel[write_counter][4], output_pixel[write_counter][5],
                           output_pixel[write_counter][6], output_pixel[write_counter][7]};
            write_counter <= (write_counter == 2'd3) ? 2'd0 : write_counter + 1;               
        end
        write_valid <= 1'b1;
    end
    else begin
        write_data <= 64'b0;
        write_valid <= 1'b0;
        write_counter <= 2'b0;
    end
end

endmodule