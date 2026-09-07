`ifndef WEIGHT_REGFILES_SV
`define WEIGHT_REGFILES_SV

// Four INT8 lanes, asynchronous read, and synchronous byte-masked write.
module Weight_Regfile #(
    parameter int DEPTH = 8,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1
)(
    input  logic clk,
    input  logic rst_n,
    input  logic [ADDR_WIDTH-1:0] read_addr,
    output logic [31:0] read_data,
    input  logic write_en,
    input  logic [3:0] write_mask,
    input  logic [ADDR_WIDTH-1:0] write_addr,
    input  logic [31:0] write_data
);
    logic [31:0] entries [0:DEPTH-1];

    assign read_data = entries[read_addr];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int entry_idx = 0; entry_idx < DEPTH; entry_idx++)
                entries[entry_idx] <= '0;
        end else if (write_en) begin
            for (int lane = 0; lane < 4; lane++)
                if (write_mask[lane])
                    entries[write_addr][8*lane +: 8] <= write_data[8*lane +: 8];
        end
    end
endmodule

`endif
