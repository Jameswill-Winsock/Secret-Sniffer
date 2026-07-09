// template to hook ntt core to real alg47910 bram

// how bram connection actually works: reference is Renesas AN-011 FIFO example

// There is NO BRAM primitive to instantiate. The hard macro's signals are
// exposed as PORTS OF YOUR (*top*) MODULE, marked (* iopad_external_pin *),
// with canonical names BRAMx_<SIG>. The fitter recognizes the names and
// wires them to the macro. They survive synthesis as ports (verified in
// post_synth_results.v -- no BRAM cell in the netlist).

// Presence of BRAMx_* ports activates BRAM block x ("Change BRAMx to
//     activate other BRAMs" -- AN-011).
// POLARITY: despite no 'n' prefix in the port names, WEN/REN/WCLKEN/RCLKEN
//     are ACTIVE LOW -- AN-011 drives BRAM0_WEN <= !WE_r, BRAM0_REN <= !RE_r.

// READ IS REGISTERED: present READ_ADDR + REN(low) on clk N, capture
//     DATA_OUT on clk N+1 (AN-011 does exactly this).

// RATIO = 2'b00 -> 512x8. We use addr {1'b0, addr[7:0]} for 256 deep.


// LAYOUT: BRAM0 = coeff low byte, BRAM1 = coeff high byte,
//         BRAM2 = twiddle low byte, BRAM3 = twiddle high byte.

(* top *) module shrike_bram_top (
    (* iopad_external_pin, clkbuf_inhibit *) input clk,
    (* iopad_external_pin *) input  nReset,
    (* iopad_external_pin *) input  start,
    (* iopad_external_pin *) output ntt_done,
    (* iopad_external_pin *) output osc_en,
    // ---- twiddle load port (driven by host interface at init) ----
    (* iopad_external_pin *) input        tw_we,
    (* iopad_external_pin *) input  [6:0] tw_waddr,
    (* iopad_external_pin *) input [15:0] tw_wdata,
    // ================= BRAM0: coeff LOW byte =================
    (* iopad_external_pin *) output [1:0] BRAM0_RATIO,
    (* iopad_external_pin *) output [7:0] BRAM0_DATA_IN,
    (* iopad_external_pin *) output       BRAM0_WEN,
    (* iopad_external_pin *) output       BRAM0_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM0_WRITE_ADDR,
    (* iopad_external_pin *) input  [7:0] BRAM0_DATA_OUT,
    (* iopad_external_pin *) output       BRAM0_REN,
    (* iopad_external_pin *) output       BRAM0_RCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM0_READ_ADDR,
    // ================= BRAM1: coeff HIGH byte ================
    (* iopad_external_pin *) output [1:0] BRAM1_RATIO,
    (* iopad_external_pin *) output [7:0] BRAM1_DATA_IN,
    (* iopad_external_pin *) output       BRAM1_WEN,
    (* iopad_external_pin *) output       BRAM1_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM1_WRITE_ADDR,
    (* iopad_external_pin *) input  [7:0] BRAM1_DATA_OUT,
    (* iopad_external_pin *) output       BRAM1_REN,
    (* iopad_external_pin *) output       BRAM1_RCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM1_READ_ADDR,
    // ================= BRAM2: twiddle LOW byte ===============
    (* iopad_external_pin *) output [1:0] BRAM2_RATIO,
    (* iopad_external_pin *) output [7:0] BRAM2_DATA_IN,
    (* iopad_external_pin *) output       BRAM2_WEN,
    (* iopad_external_pin *) output       BRAM2_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM2_WRITE_ADDR,
    (* iopad_external_pin *) input  [7:0] BRAM2_DATA_OUT,
    (* iopad_external_pin *) output       BRAM2_REN,
    (* iopad_external_pin *) output       BRAM2_RCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM2_READ_ADDR,
    // ================= BRAM3: twiddle HIGH byte ==============
    (* iopad_external_pin *) output [1:0] BRAM3_RATIO,
    (* iopad_external_pin *) output [7:0] BRAM3_DATA_IN,
    (* iopad_external_pin *) output       BRAM3_WEN,
    (* iopad_external_pin *) output       BRAM3_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM3_WRITE_ADDR,
    (* iopad_external_pin *) input  [7:0] BRAM3_DATA_OUT,
    (* iopad_external_pin *) output       BRAM3_REN,
    (* iopad_external_pin *) output       BRAM3_RCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM3_READ_ADDR
);
    assign osc_en = 1'b1;
    wire rst = ~nReset;
    assign BRAM0_RATIO = 2'b00;  assign BRAM1_RATIO = 2'b00;   // 512x8
    assign BRAM2_RATIO = 2'b00;  assign BRAM3_RATIO = 2'b00;
 
    // ntt core 
    wire bf_start, bf_done, done_w;
    wire [7:0] ba, bb, bw;
    ntt_master u_master(.clk(clk),.rst(rst),.start(start),.done(done_w),
        .bf_start(bf_start),.bf_addr_a(ba),.bf_addr_b(bb),.bf_addr_w(bw),.bf_done(bf_done));
    assign ntt_done = done_w;
 
    wire [7:0] mem_raddr, mem_waddr, tw_addr;
    wire mem_ren, mem_wen, tw_ren;
    wire [15:0] mem_wdata;
    ntt_butterfly u_bf(.clk(clk),.rst(rst),.start(bf_start),
        .addr_a(ba),.addr_b(bb),.addr_w(bw),.done(bf_done),
        .mem_raddr(mem_raddr),.mem_ren(mem_ren),.mem_rdata({BRAM1_DATA_OUT,BRAM0_DATA_OUT}),
        .mem_waddr(mem_waddr),.mem_wdata(mem_wdata),.mem_wen(mem_wen),
        .tw_addr(tw_addr),.tw_ren(tw_ren),.tw_rdata({BRAM3_DATA_OUT,BRAM2_DATA_OUT}));
 
    // coeff memory: BRAM0/1 pair (invert to active-low at the ports)
    assign BRAM0_READ_ADDR  = {1'b0, mem_raddr};
    assign BRAM1_READ_ADDR  = {1'b0, mem_raddr};
    assign BRAM0_REN        = ~mem_ren;      assign BRAM1_REN    = ~mem_ren;
    assign BRAM0_RCLKEN     = ~mem_ren;      assign BRAM1_RCLKEN = ~mem_ren;
    assign BRAM0_WRITE_ADDR = {1'b0, mem_waddr};
    assign BRAM1_WRITE_ADDR = {1'b0, mem_waddr};
    assign BRAM0_DATA_IN    = mem_wdata[7:0];
    assign BRAM1_DATA_IN    = mem_wdata[15:8];
    assign BRAM0_WEN        = ~mem_wen;      assign BRAM1_WEN    = ~mem_wen;
    assign BRAM0_WCLKEN     = ~mem_wen;      assign BRAM1_WCLKEN = ~mem_wen;
 
    // twiddle ROM: BRAM2/3 pair, written once by host, read by butterfly
    assign BRAM2_READ_ADDR  = {2'b00, tw_addr[6:0]};
    assign BRAM3_READ_ADDR  = {2'b00, tw_addr[6:0]};
    assign BRAM2_REN        = ~tw_ren;       assign BRAM3_REN    = ~tw_ren;
    assign BRAM2_RCLKEN     = ~tw_ren;       assign BRAM3_RCLKEN = ~tw_ren;
    assign BRAM2_WRITE_ADDR = {2'b00, tw_waddr};
    assign BRAM3_WRITE_ADDR = {2'b00, tw_waddr};
    assign BRAM2_DATA_IN    = tw_wdata[7:0];
    assign BRAM3_DATA_IN    = tw_wdata[15:8];
    assign BRAM2_WEN        = ~tw_we;        assign BRAM3_WEN    = ~tw_we;
    assign BRAM2_WCLKEN     = ~tw_we;        assign BRAM3_WCLKEN = ~tw_we;
endmodule


