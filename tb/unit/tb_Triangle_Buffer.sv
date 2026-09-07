`define CYCLE_TIME 6.0 // Cycle time in nanoseconds
`define PAT_NUM 1    // Number of patterns
`define MAX_LATENCY 10000 // Max latency for each pattern
`define OUT_NUM 1       // The number of output for each pattern
`define SEED 5487
`include "Triangle_Buffer.sv"

module tb_Triangle_Buffer;

//---------------------------------------------------------------------
//   PORT DECLARATION          
//---------------------------------------------------------------------
// Output Registers
reg clk, rst_n;
reg input_valid;
reg signed [7:0] input_data [0:8];

// Input Signals
reg padded_input_valid [0:8];
reg signed [7:0] padded_input_data [0:8];

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
integer i, j;


//---------------------------------------------------------------------
//   REG & WIRE DECLARATION
//---------------------------------------------------------------------

reg signed [7:0] input_in [0:8];

reg signed [31:0] expected_value [0:`PAT_NUM-1][0:8];

//---------------------------------------------------------------------
//  CLOCK
//---------------------------------------------------------------------
/* Define clock cycle */
real CYCLE = `CYCLE_TIME;
always #(CYCLE/2.0) clk = ~clk;

//---------------------------------------------------------------------
//  SIMULATION
//---------------------------------------------------------------------
Input_Buffer I1(.clk(clk), .rst_n(rst_n), 
                   .input_valid(input_valid), .input_data(input_data),
                   .padded_input_valid(padded_input_valid), .padded_input_data(padded_input_data));

initial begin
    rst_n           = 1'b1;
    total_latency   = 0;
    latency_wait     = 0;
    for(i=0; i<9; i=i+1) begin
        input_valid = 0;
    end
end

/* execution */
initial begin
    `ifdef RTL
        $fsdbDumpfile("Triangle_Buffer.fsdb");
        $fsdbDumpvars(0,"+mda");
    `endif
    `ifdef GATE
        $sdf_annotate("./Netlist/Triangle_Buffer_SYN.sdf", m1);
        $fsdbDumpfile("Triangle_Buffer_SYN.fsdb");
        $fsdbDumpvars(0,"+mda"); 
    `endif
end

initial begin
    reset_task;
    repeat (2) @(negedge clk);
    for(i_pat = 0; i_pat < patnum; i_pat = i_pat + 1) begin
        generate_input_task;
        input_task;
    end 
end

initial begin
    wait_begin_check_task;
    j_pat = 0;
    for ( j_pat = 0 ; j_pat < patnum; j_pat = j_pat + 1) begin
        check_ans_task;
    end
    YOU_PASS_task;
end

// Task to reset the system
task reset_task; begin 
    rst_n = 1'b1;
    force clk = 0;

    #(CYCLE*2.0); rst_n = 1'b0; 
    #(CYCLE*2.0); rst_n = 1'b1;

    for(i=0; i<8; i=i+1) begin
        if ((padded_input_valid[i] !== 1'b0) || (padded_input_data[i] !== 8'b0)) begin
            $display("************************************************************");
            $display("                          FAIL!                           ");
            $display("*  Output signals should be 0 after initial RESET at %8t *", $time);
            $display("************************************************************");
            repeat (2) #CYCLE;
            $finish;
        end
    end
    
    #(CYCLE*2.0); release clk;
end endtask

// Task
task generate_input_task; begin
    // GENERATE INPUT
    for(i=0; i<9; i=i+1) begin
        input_in[i] = $random(seed);
        $display("%d", input_in[i]);              
        expected_value[i_pat][i] = input_in[i];        
    end
end endtask

task input_task; begin
    @(negedge clk);
    
    input_valid = 1'b1;
    for(i=0; i<9; i=i+1) begin
        input_data[i] = input_in[i];
    end
    
    @(negedge clk);
    input_valid = 1'b0;
end endtask

task wait_begin_check_task; begin
    while(padded_input_valid[0] !== 1) begin
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

task check_ans_task; begin
    latency_out = 0;
    for(j=0; j<9; j=j+1) begin
        if(padded_input_valid[j] == 1) begin
            $display("************************************************************");  
            $display("                       End of Case!                        ");
            $display(" Column No.  :  = %d", j);               
            $display(" Expected:  = %d", expected_value[j_pat][j]);                        
            $display(" Received:  = %d", padded_input_data[j]);         
            $display("************************************************************");
            @(negedge clk); 
            latency_out = latency_out + 1;
        end
    end
end endtask

task YOU_PASS_task; begin    
    total_latency = latency_wait + latency_out;
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
