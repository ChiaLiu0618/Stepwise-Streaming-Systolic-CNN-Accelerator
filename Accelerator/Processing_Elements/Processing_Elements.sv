module upper_pe(input clk, rst_n, 
                input signed [7:0] weight_data,
                input input_in_valid, input signed [7:0] input_in_data,
                output reg input_out_valid, output reg signed [7:0] input_out_data, 
                output reg partial_sum_out_valid, output reg signed [31:0] partial_sum_out_data);

// SHIFT INPUT
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        input_out_data <= 8'b0;
        input_out_valid <= 1'b0;
    end
    else if(input_in_valid) begin
        input_out_data <= input_in_data;
        input_out_valid <= 1'b1;
    end
    else begin
        input_out_data <= 8'b0;
        input_out_valid <= 1'b0;
    end
end

// PARTIAL SUM
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        partial_sum_out_data <= 32'b0;
        partial_sum_out_valid <= 1'b0;
    end
    else if(input_in_valid) begin
        partial_sum_out_data <= input_in_data * weight_data;
        partial_sum_out_valid <= 1'b1;
    end
    else begin
        partial_sum_out_data <= 32'b0;
        partial_sum_out_valid <= 1'b0;
    end
end

endmodule

module upper_right_pe(input clk, rst_n, 
                      input signed [7:0] weight_data,
                      input input_in_valid, input signed [7:0] input_in_data, 
                      output reg partial_sum_out_valid, output reg signed [31:0] partial_sum_out_data);

// PARTIAL SUM
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        partial_sum_out_data <= 32'b0;
        partial_sum_out_valid <= 1'b0;
    end
    else if(input_in_valid) begin
        partial_sum_out_data <= input_in_data * weight_data;
        partial_sum_out_valid <= 1'b1;
    end
    else begin
        partial_sum_out_data <= 32'b0;
        partial_sum_out_valid <= 1'b0;
    end
end

endmodule

module right_pe(input clk, rst_n, 
                input signed [7:0] weight_data,
                input input_in_valid, input signed [7:0] input_in_data,
                input partial_sum_in_valid, input signed [31:0] partial_sum_in_data,
                output reg partial_sum_out_valid, output reg signed [31:0] partial_sum_out_data);

// PARTIAL SUM
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        partial_sum_out_data <= 32'b0;
        partial_sum_out_valid <= 1'b0;
    end
    else if(input_in_valid && partial_sum_in_valid) begin
        partial_sum_out_data <= input_in_data * weight_data + partial_sum_in_data;
        partial_sum_out_valid <= 1'b1;
    end
    else begin
        partial_sum_out_data <= 32'b0;
        partial_sum_out_valid <= 1'b0;
    end
end

endmodule

module standard_pe(input clk, rst_n, 
                   input signed [7:0] weight_data,
                   input input_in_valid, input signed [7:0] input_in_data,
                   input partial_sum_in_valid, input signed [31:0] partial_sum_in_data,
                   output reg input_out_valid, output reg signed [7:0] input_out_data, 
                   output reg partial_sum_out_valid, output reg signed [31:0] partial_sum_out_data);

// SHIFT INPUT
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        input_out_data <= 8'b0;
        input_out_valid <= 1'b0;
    end
    else if(input_in_valid) begin
        input_out_data <= input_in_data;
        input_out_valid <= 1'b1;
    end
    else begin
        input_out_data <= 8'b0;
        input_out_valid <= 1'b0;
    end
end

// PARTIAL SUM
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        partial_sum_out_data <= 32'b0;
        partial_sum_out_valid <= 1'b0;
    end
    else if(input_in_valid && partial_sum_in_valid) begin
        partial_sum_out_data <= input_in_data * weight_data + partial_sum_in_data;
        partial_sum_out_valid <= 1'b1;
    end
    else begin
        partial_sum_out_data <= 32'b0;
        partial_sum_out_valid <= 1'b0;
    end
end

endmodule



