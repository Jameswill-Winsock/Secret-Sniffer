// basemul - Kyber NTT-domain pointwise multiply of two polynomials A, B -> R.
// pair m=0..127 at positions (2m,2m+1):
//   r0 = fqmul(fqmul(a1,b1),zeta) + fqmul(a0,b0);  r1 = fqmul(a0,b1)+fqmul(a1,b0)
//   zeta = zetas[64+m/2], negated (q-zeta) for odd m.  Reuses one mult+REDC+ALU.
module basemul (
    input clk, input rst, input start, output done,
    output reg [7:0] a_raddr, output reg a_ren, input [15:0] a_rdata,
    output reg [7:0] b_raddr, output reg b_ren, input [15:0] b_rdata,
    output reg [7:0] z_addr,  output reg z_ren, input [15:0] z_rdata,
    output reg [7:0] r_waddr, output reg [15:0] r_wdata, output reg r_wen
);
    localparam S_IDLE=0,S_RD0=1,S_CAP0=2,S_CAP1=3,S_CAPZ=4,S_MUL=5,S_WMUL=6,
               S_WREDC=7,S_ADD=8,S_WR0=9,S_WR1=10,S_NEXT=11,S_DONE=12;
    reg [3:0] state; reg [6:0] m; reg [2:0] step;
    reg [15:0] a0,a1,b0,b1,zeta,m0,m1,r0,r1;
    wire [7:0] pos = {m,1'b0};
    wire mul_done; wire [23:0] mul_prod; reg mul_start; reg [11:0] mul_a,mul_b;
    mod_multiplier u_mul(.clk(clk),.rst(rst),.start(mul_start),.a(mul_a),.b(mul_b),.done(mul_done),.prod(mul_prod));
    wire redc_done; wire [15:0] redc_res; reg redc_start; reg [23:0] redc_tin;
    mont_redc u_redc(.clk(clk),.rst(rst),.start(redc_start),.t_in(redc_tin),.res_out(redc_res),.done(redc_done));
    wire [15:0] alu_res;
    alu u_alu(.a(m0),.b(m1),.op(1'b0),.res(alu_res));    // r = m0 + m1 mod q
    assign done = (state==S_DONE);

    always @(posedge clk) begin
        if (rst) begin state<=S_IDLE; m<=0; step<=0; end
        else case (state)
            S_IDLE: if (start) begin m<=0; state<=S_RD0; end
            S_RD0:  state<=S_CAP0;
            S_CAP0: begin a0<=a_rdata; b0<=b_rdata; state<=S_CAP1; end
            S_CAP1: begin a1<=a_rdata; b1<=b_rdata; state<=S_CAPZ; end
            S_CAPZ: begin zeta <= m[0] ? (16'd3329 - z_rdata) : z_rdata; step<=0; state<=S_MUL; end
            S_MUL:  state<=S_WMUL;
            S_WMUL: if (mul_done) state<=S_WREDC;
            S_WREDC:if (redc_done) case (step)
                        3'd0: begin m0<=redc_res; step<=1; state<=S_MUL; end
                        3'd1: begin m0<=redc_res; step<=2; state<=S_MUL; end
                        3'd2: begin m1<=redc_res; state<=S_ADD; end
                        3'd3: begin m0<=redc_res; step<=4; state<=S_MUL; end
                        default: begin m1<=redc_res; state<=S_ADD; end
                    endcase
            S_ADD:  if (step==3'd2) begin r0<=alu_res; step<=3; state<=S_WR0; end
                    else            begin r1<=alu_res; state<=S_WR1; end
            S_WR0:  state<=S_MUL;
            S_WR1:  state<=S_NEXT;
            S_NEXT: if (m==7'd127) state<=S_DONE; else begin m<=m+1; state<=S_RD0; end
            S_DONE: state<=S_IDLE;
            default:state<=S_IDLE;
        endcase
    end

    // combinational memory + block strobes
    always @(*) begin
        a_raddr=8'd0;a_ren=0;b_raddr=8'd0;b_ren=0;z_addr=8'd0;z_ren=0;
        r_waddr=8'd0;r_wdata=16'd0;r_wen=0;mul_start=0;redc_start=0;mul_a=12'd0;mul_b=12'd0;redc_tin=24'd0;
        case (state)
            S_RD0:  begin a_raddr=pos;      a_ren=1; b_raddr=pos;      b_ren=1; end
            S_CAP0: begin a_raddr=pos|8'd1; a_ren=1; b_raddr=pos|8'd1; b_ren=1; end
            S_CAP1: begin z_addr=8'd64+{1'b0,m[6:1]}; z_ren=1; end
            S_MUL:  begin mul_start=1;
                case (step)
                    3'd0: begin mul_a=a1[11:0]; mul_b=b1[11:0];   end
                    3'd1: begin mul_a=m0[11:0]; mul_b=zeta[11:0]; end
                    3'd2: begin mul_a=a0[11:0]; mul_b=b0[11:0];   end
                    3'd3: begin mul_a=a0[11:0]; mul_b=b1[11:0];   end
                    default: begin mul_a=a1[11:0]; mul_b=b0[11:0];end
                endcase end
            S_WMUL: if (mul_done) begin redc_tin=mul_prod; redc_start=1; end
            S_WR0:  begin r_waddr=pos;      r_wdata=r0; r_wen=1; end
            S_WR1:  begin r_waddr=pos|8'd1; r_wdata=r1; r_wen=1; end
            default:;
        endcase
    end
endmodule