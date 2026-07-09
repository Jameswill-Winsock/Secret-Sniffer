module mod_multiplier (
    input clk, input rst, input start,
    input [11:0] a, input [11:0] b,
    output reg done, output reg [23:0] prod
);
    localparam IDLE=3'd0, ADD_LOW=3'd1, ADD_HIGH=3'd2, SHIFT=3'd3, FINISH=3'd4;
    reg [2:0] state;
    reg [11:0] a_reg; reg [23:0] b_reg; reg [23:0] acc; reg [3:0] bit_cnt; reg carry_save;
    reg [15:0] adder_a, adder_b; reg adder_cin; wire [15:0] adder_sum; wire adder_cout;
    han_carlson u_adder(.a(adder_a),.b(adder_b),.cin(adder_cin),.sum(adder_sum),.cout(adder_cout));
    always @(*) begin
        adder_a=16'h0000; adder_b=16'h0000; adder_cin=1'b0;
        if (state==ADD_LOW) begin adder_a=acc[15:0]; adder_b=a_reg[0]?b_reg[15:0]:16'h0000; adder_cin=1'b0; end
        else if (state==ADD_HIGH) begin adder_a={8'h00,acc[23:16]}; adder_b=a_reg[0]?b_reg[23:16]:16'h0000; adder_cin=carry_save; end
    end
    always @(posedge clk) begin
        if (rst) begin state<=IDLE; done<=0; prod<=0; acc<=0; a_reg<=0; b_reg<=0; bit_cnt<=0; carry_save<=0; end
        else case (state)
            IDLE: begin done<=0; if(start) begin a_reg<=a[11:0]; b_reg<={12'h000,b}; acc<=24'h0; bit_cnt<=0; state<=ADD_LOW; end end
            ADD_LOW: begin acc[15:0]<=adder_sum; carry_save<=adder_cout; state<=ADD_HIGH; end
            ADD_HIGH: begin acc[23:16]<=adder_sum[7:0]; state<=SHIFT; end
            SHIFT: begin a_reg<=a_reg>>1; b_reg<=b_reg<<1; if(bit_cnt==11) state<=FINISH; else begin bit_cnt<=bit_cnt+1; state<=ADD_LOW; end end
            FINISH: begin prod<=acc; done<=1; state<=IDLE; end
        endcase
    end
endmodule