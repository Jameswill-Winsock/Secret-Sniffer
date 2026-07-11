// ntt_butterfly - unified butterfly. Arithmetic (mult + REDC + ALU) is now
// EXTERNAL and shared: this module drives the mul_/redc_/alu_ ports of one
// shared arithmetic core at the top level (also used by basemul). FSM and
// datapath control are unchanged from the verified version.
//
// mode 2'd0 = CT  (forward): a'=(a+t)modq, b'=(a-t)modq, t=REDC(b*w)
// mode 2'd1 = GS  (inverse): a'=(a+b)modq, b'=REDC((b-a)*w)
// mode 2'd2 = SCALE        : a'=REDC(a*F_CONST), b untouched   (n^-1 pass)
module ntt_butterfly #(
    parameter [11:0] F_CONST = 12'd512
)(
    input clk, input rst, input start, input [1:0] mode,
    input [7:0] addr_a, input [7:0] addr_b, input [7:0] addr_w, output done,
    output reg [7:0] mem_raddr, output reg mem_ren, input [15:0] mem_rdata,
    output reg [7:0] mem_waddr, output reg [15:0] mem_wdata, output reg mem_wen,
    output reg [7:0] tw_addr, output reg tw_ren, input [15:0] tw_rdata,
    // ---- shared arithmetic core (this module drives it while running) ----
    output reg        mul_start, output reg [11:0] mul_a, output reg [11:0] mul_b,
    input             mul_done,  input      [23:0] mul_prod,
    output reg        redc_start, output reg [23:0] redc_tin,
    input             redc_done, input      [15:0] redc_res,
    output reg [15:0] alu_a, output reg [15:0] alu_b, output reg alu_op,
    input      [15:0] alu_res
);
    localparam CT=2'd0, GS=2'd1, SCALE=2'd2;
    localparam S_IDLE=4'd0,S_PRE_B=4'd1,S_CAP_B=4'd2,S_CAP_A=4'd3,S_MUL=4'd4,
               S_WMUL=4'd5,S_WREDC=4'd6,S_WR_A=4'd7,S_WR_B=4'd8,S_FIN=4'd9;
    reg [3:0] state; reg [1:0] md;
    reg [7:0] a_addr_r,b_addr_r,w_addr_r; reg [15:0] a_reg,b_reg,tw_reg,t_reg;
    assign done = (state==S_FIN);
    always @(posedge clk) begin
        if (rst) state<=S_IDLE;
        else case (state)
            S_IDLE:  if (start) begin md<=mode; a_addr_r<=addr_a; b_addr_r<=addr_b; w_addr_r<=addr_w; state<=S_PRE_B; end
            S_PRE_B: state<=S_CAP_B;
            S_CAP_B: begin b_reg<=mem_rdata; tw_reg<=tw_rdata; state<=S_CAP_A; end
            S_CAP_A: begin a_reg<=mem_rdata; state<=S_MUL; end
            S_MUL:   state<=S_WMUL;
            S_WMUL:  if (mul_done)  state<=S_WREDC;
            S_WREDC: if (redc_done) begin t_reg<=redc_res; state<=S_WR_A; end
            S_WR_A:  state<=(md==SCALE) ? S_FIN : S_WR_B;
            S_WR_B:  state<=S_FIN;
            S_FIN:   state<=S_IDLE;
            default: state<=S_IDLE;
        endcase
    end
    always @(*) begin
        alu_a=a_reg; alu_b=t_reg; alu_op=1'b0;
        case (state)
            S_MUL:  if (md==GS) begin alu_a=b_reg; alu_b=a_reg; alu_op=1'b1; end
            S_WR_A: begin alu_a=a_reg; alu_b=(md==CT)?t_reg:b_reg; alu_op=1'b0; end
            S_WR_B: begin alu_a=a_reg; alu_b=t_reg; alu_op=1'b1; end
            default:;
        endcase
    end
    always @(*) begin
        mem_raddr=8'd0; mem_ren=1'b0; mem_waddr=8'd0; mem_wdata=16'd0; mem_wen=1'b0;
        tw_addr=8'd0; tw_ren=1'b0; mul_start=1'b0; redc_start=1'b0; mul_a=12'd0; mul_b=12'd0; redc_tin=24'd0;
        case (state)
            S_PRE_B: begin mem_raddr=b_addr_r; mem_ren=1'b1; tw_addr=w_addr_r; tw_ren=1'b1; end
            S_CAP_B: begin mem_raddr=a_addr_r; mem_ren=1'b1; end
            S_MUL: begin mul_start=1'b1;
                mul_b=(md==SCALE)?F_CONST:tw_reg[11:0];
                mul_a=(md==CT)?b_reg[11:0]:(md==GS)?alu_res[11:0]:a_reg[11:0]; end
            S_WMUL:  if (mul_done) begin redc_tin=mul_prod; redc_start=1'b1; end
            S_WR_A:  begin mem_waddr=a_addr_r; mem_wen=1'b1; mem_wdata=(md==SCALE)?t_reg:alu_res; end
            S_WR_B:  begin mem_waddr=b_addr_r; mem_wen=1'b1; mem_wdata=(md==CT)?alu_res:t_reg; end
            default:;
        endcase
    end
endmodule