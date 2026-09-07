`ifndef CNN_INSTRUCTIONS_SV
`define CNN_INSTRUCTIONS_SV
package Instructions;
    typedef struct packed {
        logic enable;
        logic [2:0] reserved;
        logic set_mode;
        logic fc_mode;
        logic load_weight;
        logic load_bias;
        logic load_scale;
        logic load_activation;
        logic activation_bank;
        logic [4:0] weight_addr;
    } memory_op_t;

    typedef struct packed {
        logic enable;
        logic [1:0] reserved;
        logic activation_bank;
        logic [2:0] activation_channel;
        logic [4:0] weight_addr;
        logic mac;
        logic store_result;
        logic relu;
        logic pool;
    } compute_op_t;

    typedef struct packed {
        memory_op_t mem;
        compute_op_t ops;
    } instruction_t;

    function automatic memory_op_t memory_op(
        input logic [4:0] weight_addr,
        input logic load_weight, load_bias, load_scale, load_activation,
        input logic activation_bank, set_mode, fc_mode
    );
        memory_op_t result;
        result = '0;
        result.enable = load_weight | load_bias | load_scale | load_activation | set_mode;
        result.weight_addr = weight_addr;
        result.load_weight = load_weight;
        result.load_bias = load_bias;
        result.load_scale = load_scale;
        result.load_activation = load_activation;
        result.activation_bank = activation_bank;
        result.set_mode = set_mode;
        result.fc_mode = fc_mode;
        return result;
    endfunction

    function automatic compute_op_t compute_op(
        input logic [2:0] activation_channel,
        input logic [4:0] weight_addr,
        input logic mac, store_result, relu, pool, activation_bank
    );
        compute_op_t result;
        result = '0;
        result.enable = mac | store_result | relu | pool;
        result.activation_channel = activation_channel;
        result.weight_addr = weight_addr;
        result.mac = mac;
        result.store_result = store_result;
        result.relu = relu;
        result.pool = pool;
        result.activation_bank = activation_bank;
        return result;
    endfunction

    function automatic instruction_t pack_instruction(
        input memory_op_t mem, input compute_op_t ops
    );
        return {mem, ops};
    endfunction
endpackage
`endif
