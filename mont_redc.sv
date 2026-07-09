//ver 3, again (bahahahaha, just when you think shit is fixed, NOPE)
//[FSM]  mq4_low -> mq4_high (was mq3_high);  mq4_high -> add_t_low (was mq4_low)
//[MUX]  added mq1_high, mq4_high, add_t_high cases (were falling through to default=0)
//[MUX]  mq4_low  cin: carry_flag -> 0 (was double-adding a stale carry)
//[MUX]  add_t_low add_b: mq_accumulate_high -> mq_accumulate_low; cin carry_flag -> 0
//[INST] dropped meaningless "#(16)" on han_carlson (module isn't parameterized)

//ver 2, post naive implement, changelog:
//observed a serious bug: add_a and add_b are register based, so they only take their new value on clock edge post assignment
//add_sum is combinational i.e. it reflects whatever add_a and add_b hold which was set on the previous cycle
//every state that did did "add_a <= X; add_b <= Y; result <= add_sum;" in the same clocked block was therefore latching the previous state's leftover sum into `result`, not X+Y
//had to fucking bloody simulate it in eda playground cycle by cycle BECAUSE ICARUS VERILOG SUCKS AAAAAAAAAAA
//bit 0 of t_low was silently dropped from every m computation and therefore every mqNth low and high pairs were consuming the wrong operand pairing

//so what the fix is to drop a b and cin as reg and use as wires instead, drive them combinational using a mux on "state"
//this makes add_sum correctly reflect the ACTIVE state's intended operand, in the same ACTIVE cycle only
//this is so result <= add_sum finally consumes what it is supposed to

module mont_redc(
    input clk,
    input rst,
    input start,
    input [23:0] t_in,
    output reg [15:0] res_out,
    output reg done
);

localparam [15:0] q = 16'h0D01;    //3329
localparam [15:0] qprime = 16'h0CFF; //NOT F2FF(62207); 0CFF(3327), actually qprime, since q*qprime = -1 mod 2^16

reg [3:0] state;

localparam idle = 4'd0;
localparam calcm = 4'd1; //shift & add loop for m = tlow* qnot 
localparam mq1_low = 4'd2; // add m to accumulator
localparam mq1_high = 4'd3;
localparam mq2_low = 4'd4; //add (m<<8) to accumulator
localparam mq2_high = 4'd5;
localparam mq3_low = 4'd6; //add (m<<10) to accumulator
localparam mq3_high = 4'd7; 
localparam mq4_low = 4'd8; //add (m<<11) to accumulator
localparam mq4_high = 4'd9;
localparam add_t_low = 4'd10; // u = (t+mq) >> 16 (only need carry out of lower 16 bits)
localparam add_t_high = 4'd11; // u = t_high + mq_high + carry
localparam final_sub = 4'd12; //if u>=q then u = u-q (using 2's complement add)
localparam finish = 4'd13;


//combinational operand mux: what active state wants to add, available in the same cycle add_sum is read

wire [15:0] add_sum;
wire add_cout;
reg [15:0] add_a, add_b;
reg add_cin;

han_carlson #(16) u_add(
    .a(add_a),
    .b(add_b),
    .cin(add_cin),
    .sum(add_sum),
    .cout(add_cout)
);

reg [15:0] t_low_reg;
reg [7:0] t_high_reg; // upper 8 bits of t
reg [15:0] m_accumulate;
reg [15:0] mq_accumulate_low;
reg [15:0] mq_accumulate_high; // upper bits of m*q (max 28 bits so 12 bits high)
reg [4:0] counter;
reg carry_flag;
reg [15:0] u_reg;

always @(*) begin
    add_cin = 1'b0;
    case (state)
        calcm: begin
            add_a = {m_accumulate[14:0], 1'b0};
            add_b = t_low_reg[counter] ? qprime : 16'h0000;
        end
        mq1_low: begin
            add_a = mq_accumulate_low;
            add_b = m_accumulate;
        end
        mq1_high: begin
            add_a = mq_accumulate_high;
            add_b = 16'h0000;
            add_cin = carry_flag;
        end
        mq2_low: begin
            add_a = mq_accumulate_low;
            add_b = {m_accumulate[7:0], 8'h00};
        end
        mq2_high: begin
            add_a = mq_accumulate_high;
            add_b = {8'h00, m_accumulate[15:8]};
            add_cin = carry_flag;
        end
        mq3_low: begin
            add_a = mq_accumulate_low;
            add_b = {m_accumulate[5:0], 10'h000};
        end
        mq3_high: begin
            add_a = mq_accumulate_high;
            add_b = {6'h00, m_accumulate[15:6]};
            add_cin = carry_flag;
        end
        mq4_low: begin
            add_a = mq_accumulate_low;
            add_b = {m_accumulate[4:0], 11'h000};
            add_cin = 1'b0;
        end
        mq4_high: begin
            add_a = mq_accumulate_high;
            add_b = {5'h00, m_accumulate[15:5]};
            add_cin = carry_flag;
        end
        add_t_low: begin
            add_a = t_low_reg;
            add_b = mq_accumulate_low;
            add_cin = 1'b0;
        end
        add_t_high: begin
            add_a = {8'h00, t_high_reg};
            add_b = mq_accumulate_high;
            add_cin = carry_flag;
        end
        final_sub: begin
            add_a = u_reg;
            add_b = ~q;
            add_cin = 1'b1;
        end
        default: begin
            add_a = 16'h0000;
            add_b = 16'h0000;
        end
    endcase
end

//state machine: pure sequence + latching add_sum/add_cout now that we know they will reflect this state's operands (i bloody hope so)

always @(posedge clk) begin
    if (rst) begin
        state <= idle;
        done <= 0;
    end else begin
        case (state)
            idle: begin
                done <= 0;
                if(start) begin
                    t_low_reg <= t_in[15:0];
                    t_high_reg <= t_in[23:16];
                    m_accumulate <= 0;
                    counter <= 4'd15;
                    state <= calcm;
                end
            end

        calcm: begin
            m_accumulate <= add_sum;
            if (counter == 0) begin
                state <= mq1_low;
                mq_accumulate_low <= 16'h0000;
                mq_accumulate_high <= 16'h0000;
            end else begin
                counter <= counter -1;
            end
        end

        mq1_low: begin
            mq_accumulate_low <= add_sum;
            carry_flag <= add_cout;
            state <= mq1_high;
        end
        mq1_high: begin
            mq_accumulate_high <= add_sum;
            state <= mq2_low;
        end

        mq2_low: begin
            mq_accumulate_low <= add_sum;
            carry_flag <= add_cout;
            state <= mq2_high;
        end
        mq2_high: begin
            mq_accumulate_high <= add_sum;
            state <= mq3_low;
        end

        mq3_low: begin
            mq_accumulate_low <= add_sum;
            carry_flag <= add_cout;
            state <= mq3_high;
        end
        mq3_high: begin
            mq_accumulate_high <= add_sum;
            state <= mq4_low;
        end

        mq4_low: begin
            mq_accumulate_low <= add_sum;
            carry_flag <= add_cout;
            state <= mq4_high;
        end
        mq4_high: begin
            mq_accumulate_high <= add_sum;
            state <= add_t_low;
        end

        add_t_low: begin
            carry_flag <= add_cout;
            state <= add_t_high;
        end
        add_t_high: begin
            u_reg <= add_sum;
            state <= final_sub;
        end

        final_sub: begin
            res_out <= add_cout ? add_sum : u_reg;
            done <= 1;
            state <= finish;
        end

        finish: begin
            done <= 0;
            state <= idle;
        end

        default: state <= idle;

        endcase
    end
end

endmodule
