module tb_ntt;

  //interface
  reg clk;
  reg rst;
  reg start;
  
  wire done;
  wire bf_start;
  wire bf_done;
  wire [7:0] ba;
  wire [7:0] bb;
  wire [7:0] bw;

  // master
  ntt_master u_master (
    .clk      (clk),
    .rst      (rst),
    .start    (start),
    .done     (done),
    .bf_start (bf_start),
    .bf_addr_a(ba),
    .bf_addr_b(bb),
    .bf_addr_w(bw),
    .bf_done  (bf_done)
  );

  // butterfly + its memory/twiddle interfaces
  wire [7:0]  mem_raddr;
  wire [7:0]  mem_waddr;
  wire [7:0]  tw_addr;
  wire        mem_ren;
  wire        mem_wen;
  wire        tw_ren;
  wire [15:0] mem_wdata;
  wire [15:0] mem_rdata;
  wire [15:0] tw_rdata;

  ntt_butterfly u_bf (
    .clk      (clk),
    .rst      (rst),
    .start    (bf_start),
    .addr_a   (ba),
    .addr_b   (bb),
    .addr_w   (bw),
    .done     (bf_done),
    .mem_raddr(mem_raddr),
    .mem_ren  (mem_ren),
    .mem_rdata(mem_rdata),
    .mem_waddr(mem_waddr),
    .mem_wdata(mem_wdata),
    .mem_wen  (mem_wen),
    .tw_addr  (tw_addr),
    .tw_ren   (tw_ren),
    .tw_rdata (tw_rdata)
  );

  coeff_ram u_cmem (
    .clk  (clk),
    .raddr(mem_raddr),
    .ren  (mem_ren),
    .rdata(mem_rdata),
    .waddr(mem_waddr),
    .wdata(mem_wdata),
    .wen  (mem_wen)
  );

  twiddle_rom u_trom (
    .clk  (clk),
    .addr (tw_addr),
    .ren  (tw_ren),
    .rdata(tw_rdata)
  );

  // tb vars
  integer v;
  integer idx;
  integer fails;
  integer total;
  integer c;
  
  reg [15:0] expected [0:255];

  // clkgen
  initial clk = 0;
  always #5 clk = ~clk;

  //main sequence
  initial begin
    total = 0;
    rst   = 1'b1;
    start = 1'b0;
    
    @(posedge clk);
    @(posedge clk);
    rst   = 1'b0;
    @(posedge clk);
    
    for (v = 0; v < 5; v = v + 1) begin
      // load input into coeff RAM behavioral arrays, and expected
      // load full 16-bit input properly into lo/hi:
      begin : ld
        reg [15:0] tmp [0:255];
        integer n;
        
        $readmemh($sformatf("ntt_in_%0d.hex", v), tmp);
        for (n = 0; n < 256; n = n + 1) begin
          u_cmem.ram_lo[n] = tmp[n][7:0];
          u_cmem.ram_hi[n] = tmp[n][15:8];
        end
        $readmemh($sformatf("ntt_out_%0d.hex", v), expected);
      end
      
      // run full ntt
      @(posedge clk);
      #1 start = 1'b1;
      
      @(posedge clk);
      #1 start = 1'b0;
      c = 0;
      
      while (!done && c < 200000) begin
        @(posedge clk);
        #1;
        c = c + 1;
      end
      
      // compare all 256 outputs
      fails = 0;
      for (idx = 0; idx < 256; idx = idx + 1) begin
        if ({u_cmem.ram_hi[idx], u_cmem.ram_lo[idx]} !== expected[idx]) begin
          fails = fails + 1;
          if (fails <= 6) begin
            $display("  vec%0d idx=%0d got=%0d exp=%0d", v, idx,
                     {u_cmem.ram_hi[idx], u_cmem.ram_lo[idx]}, expected[idx]);
          end
        end
      end
      
      if (fails == 0) begin
        $display("  vec%0d: PASS (256/256)  [%0d cyc]", v, c);
      end else begin
        $display("  vec%0d: FAIL %0d/256", v, fails);
      end
      total = total + fails;
    end
    
    if (total == 0) begin
      $display("FULL_NTT: PASS all 5 vectors (256-pt Kyber forward NTT vs reference)");
    end else begin
      $display("FULL_NTT: FAIL total %0d mismatches", total);
    end
    $finish;
  end

endmodule
