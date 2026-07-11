// ntt_addr_gen - address generator for both NTT schedules.
//   inv=0 : CT-DIT forward.  len=128>>layer, tw=(1<<layer)+group
//   inv=1 : GS-DIF inverse.  len=2<<layer,   tw=(1<<(7-layer))-1-group
// group = bf/len, i = bf mod len, a = group*2*len + i, b = a+len.
module ntt_addr_gen(
    input      [2:0] layer,
    input      [6:0] bf,
    input            inv,
    output     [7:0] a_addr,
    output     [7:0] b_addr,
    output     [7:0] tw_idx
);
    wire [7:0] len   = inv ? (8'd2 << layer) : (8'd128 >> layer);
    wire [7:0] mask  = len - 8'd1;
    wire [2:0] shamt = inv ? (layer + 3'd1) : (3'd7 - layer);   // log2(len)
    wire [7:0] group = bf >> shamt;
    wire [7:0] i     = bf & mask;
    assign a_addr = (group << (shamt + 3'd1)) + i;              // group*2*len + i
    assign b_addr = a_addr + len;
    assign tw_idx = inv ? ((8'd1 << (3'd7 - layer)) - 8'd1 - group)
                        : ((8'd1 << layer) + group);
endmodule