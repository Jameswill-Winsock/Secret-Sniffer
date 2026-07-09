// coeff_ram - 256x16 coefficient memory on the slg47910 bram.
//
// what i read from the slg47910 datasheet, section 9 / table 12:
//   * Each BRAM slice is 512x8, RATIO[1:0]=00. 8 slices total (BRAM0..7).
//   * It is a simple dual-port macro: one write port + one read port, usable
//     simultaneously to different addresses. It ain't two symmetric read/write
//     ports, so you cannot do two reads in one cycle from one slice-pair.
//   * read is registered: data appears on RDATA one cycle after (RADDR, nREN).
//   * All enables are ACTIVE LOW: nWEN, nREN, nWCLKEN, nRCLKEN.
//   * Real slice signals: BRAMx_nWEN, BRAMx_WADDR[8:0], BRAMx_WDATA[7:0],
//     BRAMx_nWCLKEN, REF_BRAMx_WRITE_CLK, BRAMx_WCLKINV, BRAMx_RCLKINV,
//     BRAMx_nRCLKEN, REF_BRAMx_READ_CLK, BRAMx_RDATA[7:0], BRAMx_RADDR[8:0],
//     BRAMx_nREN, BRAMx_RATIO[1:0].
//   * For 256x16: pair BRAM0 (low byte) + BRAM1 (high byte), RATIO=00,
//     address = {1'b0, addr[7:0]}.

// what i cannot confirm right now:
//   the exact way you are supposed reference the hard bram in source for the forgefpga flow --
//   i.e. the primitive/module name to instantiate, or whether the block is placed
//   and wired in goconfigure workshop's bram properties panel rather than
//   instantiated in verilog at all. the datasheet gives signal names + behavior,
//   not the source-instantiation template. get that from the forgefpga modules
//   library or a .ffpga example, and figure out how to do this shit. (i swear, they make this stuff complex and confusing on PURPOSE, so that the client doesn't BY ANY ACCIDENT actually use your product)

// TIMING FLAG: datasheet BRAM read fRD_MAX = 45 MHz worst-case (86.9 MHz typ @25C).
//   the 50 MHz target is above the worst-case read spec. Over -40/+85C the read
//   is not guaranteed at 50 MHz. Options: clock <=45 MHz, put BRAM reads on a slower
//   clock domain, or accept 25C-only. (Write fMAX is 63.9 MHz worst-case.... eh fine fuck it we ball.)

// this module is a simulation-accurate model of that interface (1W+1R, registered
// read, active-high enables here for fsm convenience -- invert to nWEN/nREN at the
// pins). swap the marked body for the real hard-macro connection at build time.
module coeff_ram (
    input             clk,
    // read port (registered, 1-cycle latency)
    input      [7:0]  raddr,
    input             ren,
    output reg [15:0] rdata,
    // write port
    input      [7:0]  waddr,
    input      [15:0] wdata,
    input             wen
);

  // ===== behavioral model (replace with real bram0/bram1 hard-macro wiring) =====
  reg [7:0] ram_lo [0:255];   // -> bram0 (ratio=00, wdata/rdata[7:0])
  reg [7:0] ram_hi [0:255];   // -> bram1

  always @(posedge clk) begin
    if (wen) begin 
      ram_lo[waddr] <= wdata[7:0]; 
      ram_hi[waddr] <= wdata[15:8]; 
    end
    if (ren) begin
      rdata <= {ram_hi[raddr], ram_lo[raddr]};   // registered read
    end
  end
  // ============================================================================

endmodule
