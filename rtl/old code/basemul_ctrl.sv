// basemul_ctrl - Kyber NTT-domain pointwise multiply, sequencer only.
// Owns no arithmetic: drives the SAME shared mult+REDC+ALU as the butterfly.
// Slim version: no fq_x/fq_y/prod latches (mul operands muxed by step, REDC fed
// combinationally from mul_prod like the butterfly), and only 3 temporaries
// (t1,tA,tB) -- ALU sums use redc_res live on the second addend.
//
// For each m=0..127 (pair 2m,2m+1), z=zetas[64+m/2], negated for odd m:
//   r0 = fqmul(fqmul(a1,b1), zz) + fqmul(a0,b0)
//   r1 = fqmul(a0,b1) + fqmul(a1,b0)
// step: 0 t1=fq(a1,b1)  1 tA=fq(t1,zz)  2 r0=tA+fq(a0,b0)   (add uses redc live)
//       3 tA=fq(a0,b1)  4 r1=tA+fq(a1,b0)                    (add uses redc live)
module basemul_ctrl (
    input  clk, input rst, input start, output done,
    output reg [7:0] a_raddr, output reg a_ren, input [15:0] a_rdata,
    output reg [7:0] a_waddr, output reg [15:0] a_wdata, output reg a_wen,
    output reg [7:0] b_raddr, output reg b_ren, input [15:0] b_rdata,
    output reg [7:0] z_addr,  output reg z_ren, input [15:0] z_rdata,
    // ---- shared arithmetic core ----
    output reg        mul_start, output reg [11:0] mul_a, output reg [11:0] mul_b,
    input             mul_done,  input      [23:0] mul_prod,
    output reg        redc_start, output reg [23:0] redc_tin,
    input             redc_done, input      [15:0] redc_res,
    output reg [15:0] alu_a, output reg [15:0] alu_b, output reg alu_op,
    input      [15:0] alu_res
);
    localparam [11:0] Q = 12'd3329;
    localparam BM_IDLE=3'd0, BM_RD0=3'd1, BM_RD1=3'd2, BM_CAP=3'd3,
               FQ_GO=3'd4, FQ_WAIT=3'd5, BM_WR=3'd6, BM_DONE=3'd7;

    reg [2:0]  state;
    reg [7:0]  m;
    reg [2:0]  step;      // 0..4 per schedule above
    reg        wr_hi;     // BM_WR phase: 0 writes r0, 1 writes r1
    reg [15:0] a0,a1,b0,b1,zz;
    reg [15:0] t1, tA, r0;

    wire [7:0] idx0 = {m[6:0],1'b0};
    wire [7:0] idx1 = {m[6:0],1'b0} | 8'd1;
    wire [7:0] zidx = 8'd64 + {1'b0,m[7:1]};

    assign done = (state==BM_DONE);

    // sums computed live: alu_a=tA(or r0 path), alu_b=redc_res
    always @(*) begin
        alu_a = tA; alu_b = redc_res; alu_op = 1'b0;
    end

    always @(posedge clk) begin
        if (rst) begin state<=BM_IDLE; m<=8'd0; step<=3'd0; wr_hi<=1'b0; end
        else case (state)
            BM_IDLE: if (start) begin m<=8'd0; state<=BM_RD0; end
            BM_RD0:  state<=BM_RD1;
            BM_RD1:  begin a0<=a_rdata; b0<=b_rdata; zz<=z_rdata; state<=BM_CAP; end
            BM_CAP:  begin a1<=a_rdata; b1<=b_rdata;
                           zz <= m[0] ? (Q - zz[11:0]) : zz;
                           step<=3'd0; state<=FQ_GO; end
            FQ_GO:   state<=FQ_WAIT;
            FQ_WAIT: if (redc_done) begin
                        case (step)
                            3'd0: begin t1<=redc_res;          step<=3'd1; state<=FQ_GO; end
                            3'd1: begin tA<=redc_res;          step<=3'd2; state<=FQ_GO; end
                            3'd2: begin r0<=alu_res;           step<=3'd3; state<=FQ_GO; end
                            3'd3: begin tA<=redc_res;          step<=3'd4; state<=FQ_GO; end
                            default: begin wr_hi<=1'b0; state<=BM_WR; end // r1=alu_res used in BM_WR
                        endcase
                     end
            BM_WR:   begin
                        if (wr_hi) begin
                            if (m==8'd127) state<=BM_DONE;
                            else begin m<=m+8'd1; state<=BM_RD0; end
                        end else wr_hi<=1'b1;
                     end
            BM_DONE: state<=BM_IDLE;
            default: state<=BM_IDLE;
        endcase
    end

    // r1 is never registered: captured at the BM_WR(hi) cycle from a register
    // written on entry. To keep it simple we register it at step-4 completion:
    reg [15:0] r1;
    always @(posedge clk) if (state==FQ_WAIT && redc_done && step==3'd4) r1<=alu_res;

    always @(*) begin
        a_raddr=8'd0; a_ren=1'b0; a_waddr=8'd0; a_wdata=16'd0; a_wen=1'b0;
        b_raddr=8'd0; b_ren=1'b0; z_addr=8'd0; z_ren=1'b0;
        mul_start=1'b0; mul_a=12'd0; mul_b=12'd0; redc_start=1'b0; redc_tin=24'd0;
        case (state)
            BM_RD0: begin a_raddr=idx0; a_ren=1'b1; b_raddr=idx0; b_ren=1'b1; z_addr=zidx; z_ren=1'b1; end
            BM_RD1: begin a_raddr=idx1; a_ren=1'b1; b_raddr=idx1; b_ren=1'b1; end
            FQ_GO:  begin mul_start=1'b1;
                        case (step)
                            3'd0: begin mul_a=a1[11:0]; mul_b=b1[11:0]; end
                            3'd1: begin mul_a=t1[11:0]; mul_b=zz[11:0]; end
                            3'd2: begin mul_a=a0[11:0]; mul_b=b0[11:0]; end
                            3'd3: begin mul_a=a0[11:0]; mul_b=b1[11:0]; end
                            default: begin mul_a=a1[11:0]; mul_b=b0[11:0]; end
                        endcase
                    end
            FQ_WAIT: if (mul_done) begin redc_tin=mul_prod; redc_start=1'b1; end
            BM_WR:  begin a_wen=1'b1;
                        if (wr_hi) begin a_waddr=idx1; a_wdata=r1; end
                        else       begin a_waddr=idx0; a_wdata=r0; end
                    end
            default:;
        endcase
    end
endmodule