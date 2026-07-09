module mod_mult (
    input clk,
    input rst,
    input start,
    input [11:0] a,
    input [11:0] b,
    output reg done,
    output reg [23:0] prod
);

//state machine params
localparam idle = 3'd0;
localparam add_low = 3'd1;
localparam add_high = 3'd2;
localparam shift = 3'd3;
localparam finish = 3'd4;

reg [2:0] state;
reg [11:0] a_reg;
reg [23:0] b_reg;
reg [23:0] acc;
reg [3:0] bit_cnt;
reg carry_save;

//interconnect signals
reg [15:0] add_a;
reg [15:0] add_b;
reg add_cin;
wire [15:0] add_sum;
wire add_cout;

han_carlson u_adder (
    .a(add_a),
    .b(add_b),
    .cin(add_cin),
    .sum(add_sum),
    .cout(add_cout)
);

always @(*) begin
    add_a = 16'h0000;
    add_b = 16'h0000;
    add_cin = 1'b0;

    if (state==add_low) begin
        add_a = acc[15:0];
        add_b = a_reg[0] ? b_reg[15:0] : 16'h0000;
        add_cin = 1'b0;
    end else if (state==add_high) begin
        add_a = {8'h00, acc[23:16]};
        add_b = a_reg[0] ? b_reg[23:16] : 16'h0000;
        add_cin = carry_save;
    end
end

always @(posedge clk) begin
    if (rst) begin
        state <= idle;
        done <= 1'b0;
        prod <= 24'h0;
        acc <= 24'h0;
        a_reg <= 12'h0;
        b_reg <= 24'h0;
        bit_cnt <= 4'd0;
        carry_save <= 1'b0;
    end else begin
        case (state)
            idle: begin
                done <= 1'b0;
                if (start) begin
                    a_reg <= a[11:0];
                    b_reg <= {12'h000, b};
                    acc <= 24'h0;
                    bit_cnt <= 4'd0;
                    state <= add_low;
                end
            end

            add_low: begin
                acc[15:0] <= add_sum;
                carry_save <= add_cout;
                state <= add_high;
            end

            add_high: begin
                acc[23:16] <= add_sum[7:0];
                state <= shift;
            end

            shift: begin
                a_reg <= a_reg>>1;
                b_reg<=b_reg<<1;
                if(bit_cnt==11) begin
                    state <= finish;
                end else begin
                    bit_cnt <= bit_cnt + 1;
                    state <= add_low;
                end
            end

            finish: begin
                prod <= acc;
                done <= 1'b1;
                state <= idle;
            end

            default: begin
                state <= idle;
            end
        endcase
    end
end 

endmodule
