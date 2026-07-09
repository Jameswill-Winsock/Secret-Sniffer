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

  integer i;
  integer cyc;
  integer maxcyc;
  integer mincyc;
  integer fails;
  reg [15:0] exp;

  initial clk = 0;
  always #5 clk = ~clk;

  // reference model
  function [15:0] ref_redc(input [23:0] t);
    reg [31:0] tlow;
    reg [31:0] m;
    reg [31:0] mq;
    reg [31:0] tt;
    reg [31:0] u;
    begin
      tt = t;
      tlow = t & 32'hFFFF;
      m = (tlow*32'd3327)&32'hFFFF;
      mq = m*32'd3329;
      u = (tt+mq)>>16;
      if (u>=32'd3329) begin
        u = u - 32'd3329;
      end
      ref_redc = u[15:0];
    end
  endfunction

  // Fixed syntax error: added semicolon
  task run(input [23:0] t);
    begin
      @(posedge clk);
      t_in = t;
      start = 1;

      @(posedge clk);
      start = 0;
      cyc = 0;

      while(!done && cyc<200) begin
        @(posedge clk);
        cyc = cyc + 1;
      end
        
      exp = ref_redc(t);

      if(!done) begin
        fails = fails+1;
        $display("hang t=%0d", t);
      end else if (res_out!==exp) begin
        fails = fails + 1;
        if (fails<=12) begin
          $display("mismatch t=%0d got=%0d expect=%0d", t, res_out, exp);
        end
      end

      if(cyc>maxcyc) maxcyc = cyc;
      if (cyc<mincyc) mincyc = cyc;

      @(posedge clk);
    end
  endtask

  // Fixed syntax error: spelled 'initial' correctly
  initial begin
    rst = 1;
    start = 0;
    t_in = 0;
    fails = 0;
    maxcyc = 0;
    mincyc = 999;

    @(posedge clk);
    @(posedge clk);
    rst = 0;
    @(posedge clk);

    // sanity checks
    run(24'd1);     // expect 169
    run(24'd65536); // expect 1
    run(24'd0);     // Fixed syntax error: relocated semicolon outside parenthesis

    for (i=0; i<30000; i=i+1) begin
      run(($random%3329)*($random%3329)&24'hFFFFFF);
    end

    // Restored the missing edge-case verification runs
    run(24'd3328*24'd3328); 
    run(24'd3328*24'd1); 
    run(24'd1665*24'd1665);

    $display("directed tests: redc(1)=%0d redc(r)=%0d redc(0)=%0d", ref_redc(1), ref_redc(65536), ref_redc(0));
    if(fails==0) begin
      $display("montgomery reduction pass latency=%0d cycles", maxcyc);
    end else begin
      $display("montgomery reduction fails fail %0d", fails);
    end
    $finish;
  end

endmodule