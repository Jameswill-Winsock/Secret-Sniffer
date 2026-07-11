// ntt_master - sequences the unified butterfly for forward or inverse NTT.
//   op_inv=0: 7 CT layers x 128 (forward).
//   op_inv=1: 7 GS layers x 128, then a 256-coeff SCALE pass (multiply by 128^-1).
module ntt_master #(parameter LAYERS=7, parameter BFLYS=128)(
    input clk, input rst, input start, input op_inv,
    output reg done,
    output reg bf_start, output reg [1:0] bf_mode,
    output reg [7:0] bf_addr_a, output reg [7:0] bf_addr_b, output reg [7:0] bf_addr_w,
    input bf_done
);
    localparam CT=2'd0, GS=2'd1, SCALE=2'd2;
    localparam M_IDLE=3'd0,M_ISSUE=3'd1,M_WAIT=3'd2,M_NEXT=3'd3,
               M_SISSUE=3'd4,M_SWAIT=3'd5,M_SNEXT=3'd6,M_DONE=3'd7;
    reg [2:0] mstate; reg [2:0] layer; reg [6:0] bidx; reg [8:0] scnt; reg inv_r;
    wire [7:0] a_i,b_i,w_i;
    ntt_addr_gen u_addr(.layer(layer),.bf(bidx),.inv(inv_r),.a_addr(a_i),.b_addr(b_i),.tw_idx(w_i));
    always @(posedge clk) begin
        if (rst) begin mstate<=M_IDLE; done<=0; bf_start<=0; layer<=0; bidx<=0; scnt<=0; end
        else begin
            bf_start<=0; done<=0;
            case (mstate)
                M_IDLE: if (start) begin inv_r<=op_inv; layer<=0; bidx<=0; scnt<=0; mstate<=M_ISSUE; end
                M_ISSUE: begin
                    bf_mode<=inv_r?GS:CT; bf_addr_a<=a_i; bf_addr_b<=b_i; bf_addr_w<=w_i;
                    bf_start<=1'b1; mstate<=M_WAIT; end
                M_WAIT: if (bf_done) mstate<=M_NEXT;
                M_NEXT: if (bidx==BFLYS-1) begin
                            bidx<=0;
                            if (layer==LAYERS-1) mstate<= inv_r ? M_SISSUE : M_DONE;
                            else begin layer<=layer+1; mstate<=M_ISSUE; end
                        end else begin bidx<=bidx+1; mstate<=M_ISSUE; end
                // ---- inverse-only: scale every coefficient by 128^-1 ----
                M_SISSUE: begin bf_mode<=SCALE; bf_addr_a<=scnt[7:0]; bf_start<=1'b1; mstate<=M_SWAIT; end
                M_SWAIT: if (bf_done) mstate<=M_SNEXT;
                M_SNEXT: if (scnt==9'd255) mstate<=M_DONE; else begin scnt<=scnt+1; mstate<=M_SISSUE; end
                M_DONE: begin done<=1'b1; mstate<=M_IDLE; end
                default: mstate<=M_IDLE;
            endcase
        end
    end
endmodule