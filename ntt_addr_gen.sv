//ntt address generator for ct-dit schedule
//give layer (0..6) and the butterfly index within the layer (0...127),
//produces the coeff pair addresses and the widdle (zeta[]) index
//len = 128 >> layer
//group = bf/len (which subblock within the layer)
//i = bf mod len (pos within the subblock)
// a = group*2*len+i, b=a+len, tw=(1<<layer) + group
//matches og kyber reference ntt() exactly
//(natural order goes in, bit reverse order comes out)

module ntt_addr_gen(
    input [2:0] layer,
    input [6:0] bf,
    output [7:0] a_addr,
    output [7:0] b_addr,
    output [7:0] tw_idx
);
wire [7:0] len = 8'd128>>layer;     //128,64,....,2
wire [7:0] mask = len - 8'd1;
wire [2:0] shamt = 3'd7 - layer;    //log2(len)
wire [7:0] group = bf >> shamt;     
wire [7:0] i = bf & mask;
assign a_addr = (group << (shamt+3'd1)) + i;    //group*2*len + i
assign b_addr = a_addr + len;
assign tw_idx = (8'd1 << layer) + group;

endmodule

