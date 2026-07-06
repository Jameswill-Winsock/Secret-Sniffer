module mont_redc(
    input clk,
    input rst,
    input start,
    input [23:0] t_in,
    output reg [15:0] res_out,
    output reg done
);

localparam q = 16'h0D01;
localparam qnot = 16'hF2FF;

wire [15:0] add_sum;
wire add_cout;
reg [15:0] add_a;
reg [15:0] add_b;
reg [15:0] add_cin;

han_carlson u_add(
    .a(add_a),
    .b(add_b),
    .cin(add_cin),
    .sum(add_sum),
    .cout(add_cout)
);

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

reg [3:0] state;

reg [15:0] t_low_reg;
reg [7:0] t_high_reg; // upper 8 bits of t
reg [15:0] m_accumulate;
reg [15:0] mq_accumulate_low;
reg [15:0] mq_accumulate_high; // upper bits of m*q (max 28 bits so 12 bits high)
reg [4:0] counter;
reg carry_flag;
reg [15:0] u_reg;

always @(posedge clk) begin
    if (rst) begin
        state <= idle;
        done <= 0;
        add_a <= 0;
        add_b <= 0;
        add_cin <= 0;
    end else begin
        case (state)
        idle: begin
            done <= 0;
            if (start) begin
                t_low_reg <= t_in[15:0];
                t_high_reg <= t_in[23:16];
                m_accumulate <= 0;
                counter <= 0;
                state <= calcm;
            end
        end

        // shift add multiplier for m = t_low * qnot
        calcm: begin
            add_a <= m_accumulate;
            add_cin <= 1'b0;

            //if lsb of t_low is 1 add qnot else add 0
            if (t_low_reg[0])
                add_b <= qnot;
            else
                add_b <= 16'h0000;

            //latch sum next cycle and shift t_low right
            m_accumulate <= add_sum;
            t_low_reg <= t_low_reg >> 1;

            if(counter==15) begin
                state <= mq1_low;
                mq_accumulate_low <= 16'h0000;
                mq_accumulate_high <= 12'h000;
            end else begin
                counter <= counter + 1;
            end
            end

            //hardcoded m*q using shifts (q=m + m<<8 + m<<10 + m<<11)
            //step 1 add m
            mq1_low: begin
                add_a <= mq_accumulate_low;
                add_b <= m_accumulate;
                add_cin <= 1'b0;
                mq_accumulate_low <= add_sum;
                carry_flag <= add_cout;
                state <= mq1_high;
            end
            mq1_high: begin
               add_a <= {4'h0, mq_accumulate_high};
               add_b <= 16'h0000;
               add_cin <= carry_flag;
               mq_accumulate_high <= add_sum[11:0];
               state <= mq2_low; 
            end

            //step 2 add m<<8
            mq2_low: begin
                add_a <= mq_accumulate_low;
                add_b <= {m_accumulate[7:0], 8'h00}; // m<<8
                add_cin <= 1'b0;
                mq_accumulate_low <= add_sum;
                carry_flag <= add_cout;
                state <= mq2_high;
            end
            mq2_high: begin
                add_a <= {4'h0, mq_accumulate_high};
                add_b <= {8'h00, m_accumulate[15:8]}; // upper bits of m<<8
                add_cin <= carry_flag;
                mq_accumulate_low <= add_sum[11:0];
                state <= mq3_low;
            end

            //step 3 add m<<10
            mq3_low: begin
                add_a <= mq_accumulate_low;
                add_b <= {m_accumulate[5:0], 10'h000}; // m<<10
                add_cin <= 1'b0;
                mq_accumulate_low <= add_sum;
                carry_flag <= add_cout;
                state <= mq3_high;
            end
            mq3_high: begin
                add_a <= {4'h0, mq_accumulate_high};
                add_b <= {8'h00, m_accumulate[15:8]}; // upper bits of m<<8
                add_cin <= carry_flag;
                mq_accumulate_low <= add_sum[11:0];
                state <= mq3_low;
            end

            //step 4 add m<<11
            mq4_low: begin
                add_a <= mq_accumulate_low;
                add_b <= {m_accumulate[4:0], 11'h000}; // m<<11
                add_cin <= 1'b0;
                mq_accumulate_low <= add_sum;
                carry_flag <= add_cout;
                state <= mq4_high;
            end
            mq4_high: begin
                add_a <= {4'h0, mq_accumulate_high};
                add_b <= {5'h00, m_accumulate[15:5]}; // upper bits of m<<11
                add_cin <= carry_flag;
                mq_accumulate_low <= add_sum[11:0];
                state <= add_t_low;
            end

            // u = (t+mq)>>16
            //drop low 16 bit since we only need carry out
            add_t_low: begin
                add_a <= t_low_reg;
                add_b <= mq_accumulate_low;
                add_cin <= 1'b0;
                carry_flag <= add_cout; // save carry for high word
                state <= final_sub;
            end

            //final redc if u>=q then u=u-q
            final_sub: begin
                // to sub q we add 2's complement ~q+1
                add_a <= u_reg;
                add_b <= ~q;
                add_cin <= 1'b1;

                //if cout 1 u>=q so we use sum
                //elif cout 0 u<q so we use u_reg
                if(add_cout)
                    res_out <= add_sum;
                else
                    res_out <= u_reg;
                done <= 1;
                state <= finish;
            end

            finish: begin
                done <= 0;
                state <= idle;
            end
        endcase
        end
    end

endmodule
