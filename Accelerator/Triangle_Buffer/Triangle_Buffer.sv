module Input_Buffer(input clk, rst_n, 
                       input input_valid, input signed [7:0] input_data [0:8],
                       output reg padded_input_valid [0:8], output reg signed [7:0] padded_input_data [0:8]);

genvar k;

// ROW 0
Buffer B0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid), .input_data(input_data[0]),
          .out_valid(padded_input_valid[0]), .out_data(padded_input_data[0]));

// ROW 1
wire signed [7:0] buffered_data_R1;
wire buffered_valid_R1;

Buffer B1_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid), .input_data(input_data[1]),
          .out_valid(buffered_valid_R1), .out_data(buffered_data_R1));

Buffer B1_1(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R1), .input_data(buffered_data_R1),
          .out_valid(padded_input_valid[1]), .out_data(padded_input_data[1]));

// ROW 2
wire signed [7:0] buffered_data_R2 [0:1];
wire buffered_valid_R2 [0:1];

Buffer B2_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid), .input_data(input_data[2]),
          .out_valid(buffered_valid_R2[0]), .out_data(buffered_data_R2[0]));

Buffer B2_1(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R2[0]), .input_data(buffered_data_R2[0]),
          .out_valid(buffered_valid_R2[1]), .out_data(buffered_data_R2[1]));

Buffer B2_2(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R2[1]), .input_data(buffered_data_R2[1]),
          .out_valid(padded_input_valid[2]), .out_data(padded_input_data[2]));

// ROW 3
wire signed [7:0] buffered_data_R3 [0:2];
wire buffered_valid_R3 [0:2];

Buffer B3_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid), .input_data(input_data[3]),
          .out_valid(buffered_valid_R3[0]), .out_data(buffered_data_R3[0]));

generate
    for(k=0; k<2; k=k+1) begin
        Buffer B3_1(.clk(clk), .rst_n(rst_n),
                  .input_valid(buffered_valid_R3[k]), .input_data(buffered_data_R3[k]),
                  .out_valid(buffered_valid_R3[k+1]), .out_data(buffered_data_R3[k+1]));
    end
endgenerate

Buffer B3_2(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R3[2]), .input_data(buffered_data_R3[2]),
          .out_valid(padded_input_valid[3]), .out_data(padded_input_data[3]));

// ROW 4
wire signed [7:0] buffered_data_R4 [0:3];
wire buffered_valid_R4 [0:3];

Buffer B4_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid), .input_data(input_data[4]),
          .out_valid(buffered_valid_R4[0]), .out_data(buffered_data_R4[0]));

generate
    for(k=0; k<3; k=k+1) begin
        Buffer B4_1(.clk(clk), .rst_n(rst_n),
                  .input_valid(buffered_valid_R4[k]), .input_data(buffered_data_R4[k]),
                  .out_valid(buffered_valid_R4[k+1]), .out_data(buffered_data_R4[k+1]));
    end
endgenerate

Buffer B4_2(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R4[3]), .input_data(buffered_data_R4[3]),
          .out_valid(padded_input_valid[4]), .out_data(padded_input_data[4]));

// ROW 5
wire signed [7:0] buffered_data_R5 [0:4];
wire buffered_valid_R5 [0:4];

Buffer B5_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid), .input_data(input_data[5]),
          .out_valid(buffered_valid_R5[0]), .out_data(buffered_data_R5[0]));

generate
    for(k=0; k<4; k=k+1) begin
        Buffer B5_1(.clk(clk), .rst_n(rst_n),
                  .input_valid(buffered_valid_R5[k]), .input_data(buffered_data_R5[k]),
                  .out_valid(buffered_valid_R5[k+1]), .out_data(buffered_data_R5[k+1]));
    end
endgenerate

Buffer B5_2(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R5[4]), .input_data(buffered_data_R5[4]),
          .out_valid(padded_input_valid[5]), .out_data(padded_input_data[5]));

// ROW 6
wire signed [7:0] buffered_data_R6 [0:5];
wire buffered_valid_R6 [0:5];

Buffer B6_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid), .input_data(input_data[6]),
          .out_valid(buffered_valid_R6[0]), .out_data(buffered_data_R6[0]));

generate
    for(k=0; k<5; k=k+1) begin
        Buffer B6_1(.clk(clk), .rst_n(rst_n),
                  .input_valid(buffered_valid_R6[k]), .input_data(buffered_data_R6[k]),
                  .out_valid(buffered_valid_R6[k+1]), .out_data(buffered_data_R6[k+1]));
    end
endgenerate

Buffer B6_2(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R6[5]), .input_data(buffered_data_R6[5]),
          .out_valid(padded_input_valid[6]), .out_data(padded_input_data[6]));

// ROW 7
wire signed [7:0] buffered_data_R7 [0:6];
wire buffered_valid_R7 [0:6];

Buffer B7_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid), .input_data(input_data[7]),
          .out_valid(buffered_valid_R7[0]), .out_data(buffered_data_R7[0]));

generate
    for(k=0; k<6; k=k+1) begin
        Buffer B7_1(.clk(clk), .rst_n(rst_n),
                  .input_valid(buffered_valid_R7[k]), .input_data(buffered_data_R7[k]),
                  .out_valid(buffered_valid_R7[k+1]), .out_data(buffered_data_R7[k+1]));
    end
endgenerate

Buffer B7_2(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R7[6]), .input_data(buffered_data_R7[6]),
          .out_valid(padded_input_valid[7]), .out_data(padded_input_data[7]));

// ROW 8
wire signed [7:0] buffered_data_R8 [0:7];
wire buffered_valid_R8 [0:7];

Buffer B8_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid), .input_data(input_data[8]),
          .out_valid(buffered_valid_R8[0]), .out_data(buffered_data_R8[0]));

generate
    for(k=0; k<7; k=k+1) begin
        Buffer B8_1(.clk(clk), .rst_n(rst_n),
                  .input_valid(buffered_valid_R8[k]), .input_data(buffered_data_R8[k]),
                  .out_valid(buffered_valid_R8[k+1]), .out_data(buffered_data_R8[k+1]));
    end
endgenerate

Buffer B8_2(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R8[7]), .input_data(buffered_data_R8[7]),
          .out_valid(padded_input_valid[8]), .out_data(padded_input_data[8]));

endmodule

module Output_Buffer(input clk, rst_n, 
                       input input_valid [0:7], input signed [7:0] input_data [0:7],
                       output reg padded_input_valid [0:7], output reg signed [7:0] padded_input_data [0:7]);

genvar k;

// Column 0
wire signed [7:0] buffered_data_R6 [0:5];
wire buffered_valid_R6 [0:5];

Buffer B6_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid[0]), .input_data(input_data[0]),
          .out_valid(buffered_valid_R6[0]), .out_data(buffered_data_R6[0]));

generate
    for(k=0; k<5; k=k+1) begin
        Buffer B6_1(.clk(clk), .rst_n(rst_n),
                  .input_valid(buffered_valid_R6[k]), .input_data(buffered_data_R6[k]),
                  .out_valid(buffered_valid_R6[k+1]), .out_data(buffered_data_R6[k+1]));
    end
endgenerate

Buffer B6_2(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R6[5]), .input_data(buffered_data_R6[5]),
          .out_valid(padded_input_valid[0]), .out_data(padded_input_data[0]));

// Column 1
wire signed [7:0] buffered_data_R5 [0:4];
wire buffered_valid_R5 [0:4];

Buffer B5_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid[1]), .input_data(input_data[1]),
          .out_valid(buffered_valid_R5[0]), .out_data(buffered_data_R5[0]));

generate
    for(k=0; k<4; k=k+1) begin
        Buffer B5_1(.clk(clk), .rst_n(rst_n),
                  .input_valid(buffered_valid_R5[k]), .input_data(buffered_data_R5[k]),
                  .out_valid(buffered_valid_R5[k+1]), .out_data(buffered_data_R5[k+1]));
    end
endgenerate

Buffer B5_2(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R5[4]), .input_data(buffered_data_R5[4]),
          .out_valid(padded_input_valid[1]), .out_data(padded_input_data[1]));

// Column 2
wire signed [7:0] buffered_data_R4 [0:3];
wire buffered_valid_R4 [0:3];

Buffer B4_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid[2]), .input_data(input_data[2]),
          .out_valid(buffered_valid_R4[0]), .out_data(buffered_data_R4[0]));

generate
    for(k=0; k<3; k=k+1) begin
        Buffer B4_1(.clk(clk), .rst_n(rst_n),
                  .input_valid(buffered_valid_R4[k]), .input_data(buffered_data_R4[k]),
                  .out_valid(buffered_valid_R4[k+1]), .out_data(buffered_data_R4[k+1]));
    end
endgenerate

Buffer B4_2(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R4[3]), .input_data(buffered_data_R4[3]),
          .out_valid(padded_input_valid[2]), .out_data(padded_input_data[2]));

// Column 3
wire signed [7:0] buffered_data_R3 [0:2];
wire buffered_valid_R3 [0:2];

Buffer B3_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid[3]), .input_data(input_data[3]),
          .out_valid(buffered_valid_R3[0]), .out_data(buffered_data_R3[0]));

generate
    for(k=0; k<2; k=k+1) begin
        Buffer B3_1(.clk(clk), .rst_n(rst_n),
                  .input_valid(buffered_valid_R3[k]), .input_data(buffered_data_R3[k]),
                  .out_valid(buffered_valid_R3[k+1]), .out_data(buffered_data_R3[k+1]));
    end
endgenerate

Buffer B3_2(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R3[2]), .input_data(buffered_data_R3[2]),
          .out_valid(padded_input_valid[3]), .out_data(padded_input_data[3]));

// Column 4
wire signed [7:0] buffered_data_R2 [0:1];
wire buffered_valid_R2 [0:1];

Buffer B2_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid[4]), .input_data(input_data[4]),
          .out_valid(buffered_valid_R2[0]), .out_data(buffered_data_R2[0]));

Buffer B2_1(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R2[0]), .input_data(buffered_data_R2[0]),
          .out_valid(buffered_valid_R2[1]), .out_data(buffered_data_R2[1]));

Buffer B2_2(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R2[1]), .input_data(buffered_data_R2[1]),
          .out_valid(padded_input_valid[4]), .out_data(padded_input_data[4]));

// Column 5
wire signed [7:0] buffered_data_R1;
wire buffered_valid_R1;

Buffer B1_0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid[5]), .input_data(input_data[5]),
          .out_valid(buffered_valid_R1), .out_data(buffered_data_R1));

Buffer B1_1(.clk(clk), .rst_n(rst_n),
          .input_valid(buffered_valid_R1), .input_data(buffered_data_R1),
          .out_valid(padded_input_valid[5]), .out_data(padded_input_data[5]));

// Column 6
Buffer B0(.clk(clk), .rst_n(rst_n),
          .input_valid(input_valid[6]), .input_data(input_data[6]),
          .out_valid(padded_input_valid[6]), .out_data(padded_input_data[6]));

// Column 7
always @(*) begin
    padded_input_data[7] = input_data[7];
    padded_input_valid[7] = input_valid[7];
end


endmodule

module Buffer(input clk, rst_n,
              input input_valid, input signed [7:0] input_data,
              output reg out_valid, output reg signed [7:0] out_data);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        out_data <= 8'b0;
        out_valid <= 1'b0;
    end
    else if(input_valid) begin
        out_data <= input_data;
        out_valid <= 1'b1;
    end
    else begin
        out_data <= out_data;
        out_valid <= 1'b0;
    end
end
    
endmodule