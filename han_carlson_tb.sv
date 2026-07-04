module han_carlson_tb();
reg [15:0] a_tb;
reg [15:0] b_tb;
reg cin_tb;
wire [15:0] sum_tb;
wire cout_tb;

integer i;
integer num_random = 2000;
integer pass_count = 0;
integer fail_count = 0;
string rand_name;

han_carlson dut(
    .a(a_tb),
    .b(b_tb),
    .cin(cin_tb),
    .sum(sum_tb),
    .cout(cout_tb)
);

initial begin
    a_tb = 16'h0000; b_tb = 16'h0000; cin_tb = 0;
    #10;
    check_result("test 1");

    a_tb = 16'h0000; b_tb = 16'h0000; cin_tb = 1;
    #10;
    check_result("test 2");

    a_tb = 16'hFFFF; b_tb = 16'h0000; cin_tb = 0;
    #10;
    check_result("test 3");

    a_tb = 16'hFFFF; b_tb = 16'h0001; cin_tb = 0;
    #10;
    check_result("test 4");

    a_tb = 16'hFFFF; b_tb = 16'hFFFF; cin_tb = 0;
    #10;
    check_result("test 5");

    a_tb = 16'hAAAA; b_tb = 16'h5555; cin_tb = 0;
    #10;
    check_result("test 6");

    a_tb = 16'hAAAA; b_tb = 16'h5555; cin_tb = 1;
    #10;
    check_result("test 7");
    for (i=0; i<num_random; i=i+1) begin
        a_tb = $random;
        b_tb = $random;
        cin_tb = $random;
        #10;
        $sformat(rand_name, "random %0d", i);
        check_result(rand_name);
    end
    $finish;
end

task check_result(input string test_name);
    reg [16:0] expected;
    begin
        expected = a_tb + b_tb + cin_tb;
        if ( {cout_tb, sum_tb} !== expected ) begin
            $display("Fail %s", test_name);
            $display("a=%h, b=%h, cin=%d", a_tb, b_tb, cin_tb);
            $display("expected sum=%h, cout=%d", expected[15:0], expected[16]);
            $display("dut sum=%h, cout=%d", sum_tb, cout_tb);
        end else begin
            $display ("pass %s", test_name);
        end
    end
endtask

endmodule
