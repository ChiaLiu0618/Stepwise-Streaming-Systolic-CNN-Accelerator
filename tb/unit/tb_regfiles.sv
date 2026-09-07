`timescale 1ns/1ps
`include "regfiles.sv"

module tb_regfiles;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 1;
    logic [2:0] read_addr = 0, write_addr = 0;
    logic [31:0] read_data, write_data = 0;
    logic write_en = 0;
    logic [3:0] write_mask = 0;
    logic [31:0] expected [0:7];
    Weight_Regfile dut (.*);

    task automatic check_all;
        for (int addr = 0; addr < 8; addr++) begin
            read_addr = 3'(addr);
            #1;
            if (read_data !== expected[addr])
                $fatal(1, "entry %0d: got %h expected %h", addr, read_data, expected[addr]);
        end
    endtask

    initial begin
        #1 rst_n = 0;
        for (int addr = 0; addr < 8; addr++) expected[addr] = 0;
        #1;
        check_all();
        @(negedge clk) rst_n = 1;
        // Load all 32 logical pages, preserving the other three byte lanes.
        for (int page = 0; page < 32; page++) begin
            @(negedge clk);
            write_en = 1;
            write_addr = 3'(page);
            write_mask = 4'b1 << (page / 8);
            write_data = {4{8'(page * 7 + 128)}};
            read_addr = write_addr;
            #1;
            if (read_data !== expected[write_addr]) $fatal(1, "write occurred before edge");
            @(posedge clk);
            expected[write_addr][8*(page/8) +: 8] = 8'(page * 7 + 128);
            #1;
            if (read_data !== expected[write_addr]) $fatal(1, "masked write failed");
        end
        @(negedge clk) write_en = 0;
        check_all();
        // Disabled writes and a zero byte mask must leave every entry intact.
        @(negedge clk);
        write_data = '1;
        @(posedge clk);
        #1;
        check_all();
        @(negedge clk);
        write_en = 1;
        write_mask = 0;
        @(posedge clk);
        #1;
        check_all();
        // All lanes may be written together.
        @(negedge clk);
        write_mask = '1;
        write_addr = 3;
        write_data = 32'h807fff00;
        @(posedge clk);
        expected[3] = write_data;
        #1;
        check_all();
        // Asynchronous reset wins even with a write pending.
        rst_n = 0;
        for (int addr = 0; addr < 8; addr++) expected[addr] = 0;
        #1;
        check_all();
        $display("PASS: all entries, byte masks, retention, read/write timing, and reset");
        $finish;
    end
endmodule
