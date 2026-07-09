// mont_redc v3 - bug fixes over v2:
//  [FSM]  mq4_low -> mq4_high (was mq3_high);  mq4_high -> add_t_low (was mq4_low)
//  [MUX]  added mq1_high, mq4_high, add_t_high cases (were falling through to default=0)
//  [MUX]  mq4_low  cin: carry_flag -> 0 (was double-adding a stale carry)
//  [MUX]  add_t_low add_b: mq_accumulate_high -> mq_accumulate_low; cin carry_flag -> 0
//  [INST] dropped meaningless "#(16)" on han_carlson (module isn't parameterized)
module mont_redc(
    input clk, input rst, input start,
    input [23:0] t_in, output reg [15:0] res_out, output reg done
);
localparam [15:0] q = 16'h0D01;      // 3329
localparam [15:0] qprime = 16'h0CFF; // 3327 ; q*qprime = -1 mod 2^16
reg [3:0] state;
localparam idle=4'd0, calcm=4'd1, mq1_low=4'd2, mq1_high=4'd3, mq2_low=4'd4,
           mq2_high=4'd5, mq3_low=4'd6, mq3_high=4'd7, mq4_low=4'd8, mq4_high=4'd9,
           add_t_low=4'd10, add_t_high=4'd11, final_sub=4'd12, finish=4'd13;
wire [15:0] add_sum; wire add_cout; reg [15:0] add_a, add_b; reg add_cin;
han_carlson u_add(.a(add_a),.b(add_b),.cin(add_cin),.sum(add_sum),.cout(add_cout));
reg [15:0] t_low_reg; reg [7:0] t_high_reg; reg [15:0] m_accumulate;
reg [15:0] mq_accumulate_low; reg [15:0] mq_accumulate_high; reg [4:0] counter;
reg carry_flag; reg [15:0] u_reg;
always @(*) begin
    add_cin = 1'b0; add_a = 16'h0000; add_b = 16'h0000;
    case (state)
        calcm:     begin add_a={m_accumulate[14:0],1'b0};      add_b=t_low_reg[counter]?qprime:16'h0000; end
        mq1_low:   begin add_a=mq_accumulate_low;              add_b=m_accumulate; end
        mq1_high:  begin add_a=mq_accumulate_high;             add_b=16'h0000;                 add_cin=carry_flag; end
        mq2_low:   begin add_a=mq_accumulate_low;              add_b={m_accumulate[7:0],8'h00}; end
        mq2_high:  begin add_a=mq_accumulate_high;             add_b={8'h00,m_accumulate[15:8]}; add_cin=carry_flag; end
        mq3_low:   begin add_a=mq_accumulate_low;              add_b={m_accumulate[5:0],10'h000}; end
        mq3_high:  begin add_a=mq_accumulate_high;             add_b={6'h00,m_accumulate[15:6]}; add_cin=carry_flag; end
        mq4_low:   begin add_a=mq_accumulate_low;              add_b={m_accumulate[4:0],11'h000}; end
        mq4_high:  begin add_a=mq_accumulate_high;             add_b={5'h00,m_accumulate[15:5]}; add_cin=carry_flag; end
        add_t_low: begin add_a=t_low_reg;                      add_b=mq_accumulate_low; end
        add_t_high:begin add_a={8'h00,t_high_reg};             add_b=mq_accumulate_high;         add_cin=carry_flag; end
        final_sub: begin add_a=u_reg;                          add_b=~q;                         add_cin=1'b1; end
        default:   begin add_a=16'h0000; add_b=16'h0000; end
    endcase
end
always @(posedge clk) begin
    if (rst) begin state<=idle; done<=0; end
    else begin case (state)
        idle:      begin done<=0; if(start) begin t_low_reg<=t_in[15:0]; t_high_reg<=t_in[23:16]; m_accumulate<=0; counter<=4'd15; state<=calcm; end end
        calcm:     begin m_accumulate<=add_sum; if(counter==0) begin state<=mq1_low; mq_accumulate_low<=16'h0000; mq_accumulate_high<=16'h0000; end else counter<=counter-1; end
        mq1_low:   begin mq_accumulate_low<=add_sum;  carry_flag<=add_cout; state<=mq1_high; end
        mq1_high:  begin mq_accumulate_high<=add_sum;                       state<=mq2_low; end
        mq2_low:   begin mq_accumulate_low<=add_sum;  carry_flag<=add_cout; state<=mq2_high; end
        mq2_high:  begin mq_accumulate_high<=add_sum;                       state<=mq3_low; end
        mq3_low:   begin mq_accumulate_low<=add_sum;  carry_flag<=add_cout; state<=mq3_high; end
        mq3_high:  begin mq_accumulate_high<=add_sum;                       state<=mq4_low; end
        mq4_low:   begin mq_accumulate_low<=add_sum;  carry_flag<=add_cout; state<=mq4_high; end
        mq4_high:  begin mq_accumulate_high<=add_sum;                       state<=add_t_low; end
        add_t_low: begin                              carry_flag<=add_cout; state<=add_t_high; end
        add_t_high:begin u_reg<=add_sum;                                    state<=final_sub; end
        final_sub: begin res_out<=add_cout?add_sum:u_reg; done<=1;          state<=finish; end
        finish:    begin done<=0;                                          state<=idle; end
        default:   state<=idle;
    endcase end
end
endmodule