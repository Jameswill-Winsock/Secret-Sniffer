`timescale 1ns/1ps
module mont_redc_tb;

reg clk, rst, start;
reg [23:0] t_in;
wire [15:0] res_out;
wire done;

mont_redc dut(
    .clk(clk),
    .rst(rst),
    .start(start),
    .t_in(t_in),
    .res_out(res_out),
    .done(done)
);

always #5 clk = ~clk;

integer f;
integer r;
integer expected;
integer pass_count;
integer fail_count;
integer total;

initial begin
    clk = 0; rst = 1; start= 0; t_in = 0;
    repeat (3) @(negedge clk);
    rst = 0;
    @(negedge clk);

    f=$fopen("vectors.txt", "r");
    pass_count = 0; fail_count = 0; total = 0;

    while(!$feof(f)) begin
        r = $fscanf(f, "%d %d\n", t_in, expected);
        if (r==2) begin
            start = 1;
            @(negedge clk);
            start = 0;
            while(!done) @(negedge clk);

            total = total+1;
            if (res_out !== expected[15:0]) begin
                fail_count = fail_count + 1;
                if(fail_count <= 10)
                    $display("fail: t_in=%0d expected=%0d got=%0d", t_in, expected, res_out);
            end else begin
                pass_count = pass_count + 1;
            end

            @(negedge clk);
        end
    end
    $fclose(f);
    $display("total=%0d pass=%0d fail=%0d", total, pass_count, fail_count);
    $finish;
end

endmodule