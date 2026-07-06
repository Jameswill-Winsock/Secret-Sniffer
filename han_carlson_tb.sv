`timescale 1ns/1ps

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

    han_carlson dut(
        .a(a_tb),
        .b(b_tb),
        .cin(cin_tb),
        .sum(sum_tb),
        .cout(cout_tb)
    );

    initial begin
        // Edge Cases
        a_tb = 16'h0000; b_tb = 16'h0000; cin_tb = 0; #10; check_result("zero, cin0");
        a_tb = 16'h0000; b_tb = 16'h0000; cin_tb = 1; #10; check_result("zero, cin1");
        a_tb = 16'hFFFF; b_tb = 16'h0000; cin_tb = 0; #10; check_result("max, cin0");
        a_tb = 16'hFFFF; b_tb = 16'h0001; cin_tb = 0; #10; check_result("max+1 overflow");
        a_tb = 16'hFFFF; b_tb = 16'hFFFF; cin_tb = 0; #10; check_result("max+max");
        a_tb = 16'hFFFF; b_tb = 16'hFFFF; cin_tb = 1; #10; check_result("max+max+cin");
        a_tb = 16'hAAAA; b_tb = 16'h5555; cin_tb = 0; #10; check_result("alt bits");
        
        // Random Regression
        for (i=0; i<num_random; i=i+1) begin
            a_tb = $random;
            b_tb = $random;
            cin_tb = $random;
            #10;
            check_result($sformatf("random %0d", i));
        end

        $display("==================================================");
        $display("Regression done: %0d passed, %0d failed", pass_count, fail_count);
        $display("==================================================");
        $finish;
    end

    task automatic check_result(input string test_name);
        reg [16:0] expected;
        begin
            expected = a_tb + b_tb + cin_tb;
            if ({cout_tb, sum_tb} !== expected) begin
                fail_count = fail_count + 1;
                $error("Fail %s | a=%h b=%h cin=%b | expected %h%h | got %h%h", 
                      test_name, a_tb, b_tb, cin_tb, expected[16], expected[15:0], cout_tb, sum_tb);
            end else begin
                pass_count = pass_count + 1;
            end
        end
    endtask

endmodule