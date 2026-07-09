// twiddle_rom - kyber zetas[128], montgomery form (w*r mod q), registered read.
// on the SLG47910 this maps to one 512x8 bram slice-pair (256x16 used partially),
module twiddle_rom (
    input             clk,
    input      [7:0]  addr,
    input             ren,
    output reg [15:0] rdata
);
    reg [15:0] rom [0:127];
    initial $readmemh("zetas.hex", rom);
    always @(posedge clk) if (ren) rdata <= rom[addr[6:0]];
endmodule
