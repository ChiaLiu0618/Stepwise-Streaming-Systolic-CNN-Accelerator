`include "Processing_Elements.sv"
module Systolic_Array(input clk, rst_n, 
                      input signed [7:0] weight_data [0:8][0:7],
                      input padded_input_valid [0:8], input signed [7:0] padded_input_data [0:8],
                      output reg sum_valid [0:7], output reg signed [31:0] sum_out [0:7]);

genvar k, l;

wire input_out_valid [0:8][0:6];    // [row][column]
wire signed [7:0] input_out_data [0:8][0:6];
wire partial_sum_out_valid [0:7][0:7];
wire signed [31:0] partial_sum_out_data [0:7][0:7];

// UPPER LAYER PE
upper_pe UL1(.clk(clk), .rst_n(rst_n),       // UPPER LAYER PE 0
            .weight_data(weight_data[0][0]),
            .input_in_valid(padded_input_valid[0]), .input_in_data(padded_input_data[0]),
            .input_out_valid(input_out_valid[0][0]), .input_out_data(input_out_data[0][0]),
            .partial_sum_out_valid(partial_sum_out_valid[0][0]), .partial_sum_out_data(partial_sum_out_data[0][0]));

generate 
    for(k = 1 ; k < 7 ; k = k + 1) begin    // UPPER LAYER PE 1~6
        upper_pe U1(.clk(clk), .rst_n(rst_n),
                    .weight_data(weight_data[0][k]),
                    .input_in_valid(input_out_valid[0][k-1]), .input_in_data(input_out_data[0][k-1]),
                    .input_out_valid(input_out_valid[0][k]), .input_out_data(input_out_data[0][k]),
                    .partial_sum_out_valid(partial_sum_out_valid[0][k]), .partial_sum_out_data(partial_sum_out_data[0][k]));
    end
endgenerate

upper_right_pe UR1(.clk(clk), .rst_n(rst_n),    // UPPER LAYER PE 7
                   .weight_data(weight_data[0][7]),
                   .input_in_valid(input_out_valid[0][6]), .input_in_data(input_out_data[0][6]), 
                   .partial_sum_out_valid(partial_sum_out_valid[0][7]), .partial_sum_out_data(partial_sum_out_data[0][7]));

// STANDARD PE
generate 
    for(l = 1 ; l < 8 ; l = l + 1) begin        // PE LAYER 1~7 
        standard_pe L1(.clk(clk), .rst_n(rst_n),    // PE 0
                       .weight_data(weight_data[l][0]),
                       .input_in_valid(padded_input_valid[l]), .input_in_data(padded_input_data[l]),
                       .partial_sum_in_valid(partial_sum_out_valid[l-1][0]), .partial_sum_in_data(partial_sum_out_data[l-1][0]),
                       .input_out_valid(input_out_valid[l][0]), .input_out_data(input_out_data[l][0]), 
                       .partial_sum_out_valid(partial_sum_out_valid[l][0]), .partial_sum_out_data(partial_sum_out_data[l][0]));  
                
        for(k = 1 ; k < 7 ; k = k + 1) begin        // PE 1~6
            standard_pe S1(.clk(clk), .rst_n(rst_n),
                           .weight_data(weight_data[l][k]),
                           .input_in_valid(input_out_valid[l][k-1]), .input_in_data(input_out_data[l][k-1]),
                           .partial_sum_in_valid(partial_sum_out_valid[l-1][k]), .partial_sum_in_data(partial_sum_out_data[l-1][k]),
                           .input_out_valid(input_out_valid[l][k]), .input_out_data(input_out_data[l][k]), 
                           .partial_sum_out_valid(partial_sum_out_valid[l][k]), .partial_sum_out_data(partial_sum_out_data[l][k]));
        end

        right_pe R1(.clk(clk), .rst_n(rst_n),               // PE 7
                    .weight_data(weight_data[l][7]),
                    .input_in_valid(input_out_valid[l][6]), .input_in_data(input_out_data[l][6]),
                    .partial_sum_in_valid(partial_sum_out_valid[l-1][7]), .partial_sum_in_data(partial_sum_out_data[l-1][7]),
                    .partial_sum_out_valid(partial_sum_out_valid[l][7]), .partial_sum_out_data(partial_sum_out_data[l][7]));   
    end
endgenerate

// BOTTOM LAYER PE
standard_pe BL1(.clk(clk), .rst_n(rst_n),    // BOTTOM LAYER PE 0
               .weight_data(weight_data[8][0]),
               .input_in_valid(padded_input_valid[8]), .input_in_data(padded_input_data[8]),
               .partial_sum_in_valid(partial_sum_out_valid[7][0]), .partial_sum_in_data(partial_sum_out_data[7][0]),
               .input_out_valid(input_out_valid[8][0]), .input_out_data(input_out_data[8][0]), 
               .partial_sum_out_valid(sum_valid[0]), .partial_sum_out_data(sum_out[0]));

generate
    for(k = 1 ; k < 7 ; k = k + 1) begin        // BOTTOM LAYER PE 1~6
        standard_pe B1(.clk(clk), .rst_n(rst_n),
                       .weight_data(weight_data[8][k]),
                       .input_in_valid(input_out_valid[8][k-1]), .input_in_data(input_out_data[8][k-1]),
                       .partial_sum_in_valid(partial_sum_out_valid[7][k]), .partial_sum_in_data(partial_sum_out_data[7][k]),
                       .input_out_valid(input_out_valid[8][k]), .input_out_data(input_out_data[8][k]), 
                       .partial_sum_out_valid(sum_valid[k]), .partial_sum_out_data(sum_out[k]));
    end
endgenerate

right_pe BR1(.clk(clk), .rst_n(rst_n),               // BOTTOM LAYER PE 7
            .weight_data(weight_data[8][7]),
            .input_in_valid(input_out_valid[8][6]), .input_in_data(input_out_data[8][6]),
            .partial_sum_in_valid(partial_sum_out_valid[7][7]), .partial_sum_in_data(partial_sum_out_data[7][7]),
            .partial_sum_out_valid(sum_valid[7]), .partial_sum_out_data(sum_out[7])); 

endmodule