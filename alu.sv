module alu (
    input [15:0] a,
    input [15:0] b,
    input op,
    output reg [15:0] res
);
wire [15:0] sum1;
wire cout1;
wire [15:0] sum2;
wire cout2;

wire [15:0] b1 = op ? ~b : b;
wire cin1 = op ? 1'b1 : 1'b0;

han_carlson u_stage1 (
    .a(a),
    .b(b1),
    .cin(cin1),
    .sum(sum1),
    .cout(cout1)
);

wire [15:0] b2 = op ? 16'h0D01 : 16'hF2FF;
wire cin2 = 1'b0;

han_carlson u_stage2 (
    .a(sum1),
    .b(b2),
    .cin(cin2),
    .sum(sum2),
    .cout(cout2)
);

wire use_sum2 = op ? ~cout1 : cout2;
assign res = use_sum2 ? sum2 : sum1;

endmodule
