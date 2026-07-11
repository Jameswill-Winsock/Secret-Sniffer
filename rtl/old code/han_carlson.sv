module han_carlson (
    input [15:0] a,
    input [15:0] b,
    input cin,
    output [15:0] sum,
    output cout
);
    wire [15:0] g;
    wire [15:0] p;
    assign g = a & b;
    assign p = a ^ b;

    // array to represent i through k instead of going through each wire manually (like i was trying to stupidly in logisim)
    wire G[16][16];
    wire P[16][16];

    //use genvar and generate to just define it high level once instead of copy pasting like a mad man (oooh spooky magical new keyword i discover today)
    genvar i;
    // lvl0 - basegen for singular bits
    generate
        for (i=0; i<16; i= i+1) begin: base
            assign G[i][i] = g[i];
            assign P[i][i] = p[i];
        end
    endgenerate

    // lvl1 - outer neighbor pairs (hancarlson oddindexed rows)
    generate
        for (i=1; i<16; i= i + 2) begin: l1
            assign G[i][i-1] = G[i][i] | (P[i][i] & G[i-1][i-1]);
            assign P[i][i-1] = P[i][i] & P[i-1][i-1];
        end
    endgenerate

    // lvl2 - black cells span dist of 2
    generate
        for(i=3; i<16; i= i + 2) begin: l2
            assign G[i][i-3] = G[i][i-1] | (P[i][i-1] & G[i-2][i-3]);
            assign P[i][i-3] = P[i][i-1] & P[i-2][i-3];
        end
    endgenerate

    // lvl3 - black cells span distance of 4
    generate
        for(i=7; i<16; i= i + 2) begin: l3
            assign G[i][i-7] = G[i][i-3] | (P[i][i-3] & G[i-4][i-7]);
            assign P[i][i-7] = P[i][i-3] & P[i-4][i-7];
        end
    endgenerate

    wire [15:0] C;
    assign C[0] = cin;

    // carrygen logic
    // precompute C[i] = G[i-1][0] | (P[i-1][0] & cin) for l1,l2,l3 to do the parallel prefix work and jump ahead, to calc all sums simultaneously, as opposed to traditional ripple carry system
    // also, since we're using a carry tree instead of carry look ahead logic blocks, this should theoretically reduce fanout and speed it up compared to whatever that mess was that i made of a 4 block 4 bit carry look ahead adder, with 2 stage look ahead carry logic block
    // only minor rippling for the gaps

    //fixed: c[i] is carry INTO bit i.e. the group (i-1):0 g/p
    //i ended up doing the opposite lol
    assign C[1] = g[0] | (p[0] & C[0]);

    assign C[2] = G[1][0] | (P[1][0] & C[0]);

    wire G_2_0 = g[2] | (p[2] & G[1][0]);
    wire P_2_0 = p[2] & P[1][0];
    assign C[3] = G_2_0 | (P_2_0 & C[0]);

    assign C[4] = G[3][0] | (P[3][0] & C[0]);

    wire G_4_0 = g[4] | (p[4] & G[3][0]);
    wire P_4_0 = p[4] & P[3][0];
    assign C[5] = G_4_0 | (P_4_0 & C[0]);

    wire G_5_0 = g[5] | (p[5] & G_4_0);
    wire P_5_0 = p[5] & P_4_0;
    assign C[6] = G_5_0 | (P_5_0 & C[0]);

    wire G_6_0 = g[6] | (p[6] & G_5_0);
    wire P_6_0 = p[6] & P_5_0;
    assign C[7] = G_6_0 | (P_6_0 & C[0]);

    assign C[8] = G[7][0] | (P[7][0] & C[0]);

    wire G_8_0 = g[8] | (p[8] & G[7][0]);
    wire P_8_0 = p[8] & P[7][0];
    assign C[9] = G_8_0 | (P_8_0 & C[0]);

    wire G_9_0 = g[9] | (p[9] & G_8_0);
    wire P_9_0 = p[9] & P_8_0; 
    assign C[10] = G_9_0 | (P_9_0 & C[0]); 

    wire G_10_0 = g[10] | (p[10] & G_9_0);
    wire P_10_0 = p[10] & P_9_0;
    assign C[11] = G_10_0 | (P_10_0 & C[0]);

    wire G_11_0 = g[11] | (p[11] & G_10_0);
    wire P_11_0 = p[11] & P_10_0;
    assign C[12] = G_11_0 | (P_11_0 & C[0]);

    wire G_12_0 = g[12] | (p[12] & G_11_0);
    wire P_12_0 = p[12] & P_11_0;
    assign C[13] = G_12_0 | (P_12_0 & C[0]);

    wire G_13_0 = g[13] | (p[13] & G_12_0);
    wire P_13_0 = p[13] & P_12_0;
    assign C[14] = G_13_0 | (P_13_0 & C[0]);

    wire G_14_0 = g[14] | (p[14] & G_13_0);
    wire P_14_0 = p[14] & P_13_0;
    assign C[15] = G_14_0 | (P_14_0 & C[0]);

    wire G_15_0 = g[15] | (p[15] & G_14_0);
    wire P_15_0 = p[15] & P_14_0;

    // final cout and sum
    assign cout = G_15_0 | (P_15_0 & C[0]);

    genvar k;
    generate
        for(k=0; k<16; k=k+1) begin: sumgen
            assign sum[k] = p[k] ^ C[k];
        end
    endgenerate

endmodule