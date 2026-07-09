// ============================================================================
//  shrike_ntt_top - Kyber forward/inverse NTT + basemul accelerator
//  RP2040  <--SPI-->  FPGA  <-->  SLG47910 BRAM hard macros
//
//  BRAM map (RATIO=00, 512x8 each, all enables active-LOW, registered read):
//    BRAM0/1 = operand A / coefficient buffer  (lo / hi byte)
//    BRAM2/3 = twiddle ROM  zetas[0..127]       (lo / hi byte)
//    BRAM4/5 = operand B  (second poly, basemul)(lo / hi byte)
//
//  Command set (1 opcode byte, then payload; each byte = one SPI exchange):
//    0x10 LOAD_A    : 512 bytes -> A      (lo,hi,...)
//    0x11 LOAD_B    : 512 bytes -> B      (lo,hi,...)
//    0x20 LOAD_ZETA : 256 bytes -> zetas  (lo,hi,...)
//    0x30 START_FWD : forward NTT on A
//    0x31 START_INV : inverse NTT on A
//    0x32 START_BMUL: basemul  A (*) B -> A
//    0x40 STATUS    : next MISO byte = {7'b0, done}
//    0x50 READ_A    : 512 bytes <- A  (result, lo,hi,...)
// ============================================================================
(* top *) module shrike_ntt_top (
    (* iopad_external_pin, clkbuf_inhibit *) input  clk,
    (* iopad_external_pin *)                 output clk_en,
    (* iopad_external_pin *)                 input  rst_n,

    // ---- SPI (RP2040 is controller) ----
    (* iopad_external_pin *) input  spi_ss_n,
    (* iopad_external_pin *) input  spi_sck,
    (* iopad_external_pin *) input  spi_mosi,
    (* iopad_external_pin *) output spi_miso,
    (* iopad_external_pin *) output spi_miso_en,

    // ---- BRAM0 : coeff/A low byte ----
    (* iopad_external_pin *) output [1:0] BRAM0_RATIO,
    (* iopad_external_pin *) output [7:0] BRAM0_DATA_IN,
    (* iopad_external_pin *) output       BRAM0_WEN,
    (* iopad_external_pin *) output       BRAM0_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM0_WRITE_ADDR,
    (* iopad_external_pin *) input  [7:0] BRAM0_DATA_OUT,
    (* iopad_external_pin *) output       BRAM0_REN,
    (* iopad_external_pin *) output       BRAM0_RCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM0_READ_ADDR,
    // ---- BRAM1 : coeff/A high byte ----
    (* iopad_external_pin *) output [1:0] BRAM1_RATIO,
    (* iopad_external_pin *) output [7:0] BRAM1_DATA_IN,
    (* iopad_external_pin *) output       BRAM1_WEN,
    (* iopad_external_pin *) output       BRAM1_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM1_WRITE_ADDR,
    (* iopad_external_pin *) input  [7:0] BRAM1_DATA_OUT,
    (* iopad_external_pin *) output       BRAM1_REN,
    (* iopad_external_pin *) output       BRAM1_RCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM1_READ_ADDR,
    // ---- BRAM2 : twiddle low byte ----
    (* iopad_external_pin *) output [1:0] BRAM2_RATIO,
    (* iopad_external_pin *) output [7:0] BRAM2_DATA_IN,
    (* iopad_external_pin *) output       BRAM2_WEN,
    (* iopad_external_pin *) output       BRAM2_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM2_WRITE_ADDR,
    (* iopad_external_pin *) input  [7:0] BRAM2_DATA_OUT,
    (* iopad_external_pin *) output       BRAM2_REN,
    (* iopad_external_pin *) output       BRAM2_RCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM2_READ_ADDR,
    // ---- BRAM3 : twiddle high byte ----
    (* iopad_external_pin *) output [1:0] BRAM3_RATIO,
    (* iopad_external_pin *) output [7:0] BRAM3_DATA_IN,
    (* iopad_external_pin *) output       BRAM3_WEN,
    (* iopad_external_pin *) output       BRAM3_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM3_WRITE_ADDR,
    (* iopad_external_pin *) input  [7:0] BRAM3_DATA_OUT,
    (* iopad_external_pin *) output       BRAM3_REN,
    (* iopad_external_pin *) output       BRAM3_RCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM3_READ_ADDR,
    // ---- BRAM4 : operand B low byte ----
    (* iopad_external_pin *) output [1:0] BRAM4_RATIO,
    (* iopad_external_pin *) output [7:0] BRAM4_DATA_IN,
    (* iopad_external_pin *) output       BRAM4_WEN,
    (* iopad_external_pin *) output       BRAM4_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM4_WRITE_ADDR,
    (* iopad_external_pin *) input  [7:0] BRAM4_DATA_OUT,
    (* iopad_external_pin *) output       BRAM4_REN,
    (* iopad_external_pin *) output       BRAM4_RCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM4_READ_ADDR,
    // ---- BRAM5 : operand B high byte ----
    (* iopad_external_pin *) output [1:0] BRAM5_RATIO,
    (* iopad_external_pin *) output [7:0] BRAM5_DATA_IN,
    (* iopad_external_pin *) output       BRAM5_WEN,
    (* iopad_external_pin *) output       BRAM5_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM5_WRITE_ADDR,
    (* iopad_external_pin *) input  [7:0] BRAM5_DATA_OUT,
    (* iopad_external_pin *) output       BRAM5_REN,
    (* iopad_external_pin *) output       BRAM5_RCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM5_READ_ADDR
);

    assign clk_en = 1'b1;
    wire rst = ~rst_n;

    assign BRAM0_RATIO = 2'b00;
    assign BRAM1_RATIO = 2'b00;
    assign BRAM2_RATIO = 2'b00;
    assign BRAM3_RATIO = 2'b00;
    assign BRAM4_RATIO = 2'b00;
    assign BRAM5_RATIO = 2'b00;

    // combined 16-bit read data
    wire [15:0] a_rdata  = {BRAM1_DATA_OUT, BRAM0_DATA_OUT};   // coeff / operand A
    wire [15:0] tw_rdata = {BRAM3_DATA_OUT, BRAM2_DATA_OUT};   // twiddle
    wire [15:0] b_rdata  = {BRAM5_DATA_OUT, BRAM4_DATA_OUT};   // operand B

    // ------------------------------------------------------------------------
    //  SPI target (canonical Shrike module, mode 0, MSB, 8-bit)
    // ------------------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_valid;
    reg  [7:0] tx_byte;

    spi_target #(.CPOL(0), .CPHA(0), .WIDTH(8), .LSB(0)) u_spi (
        .i_clk          (clk),
        .i_rst_n        (rst_n),
        .i_enable       (1'b1),
        .i_ss_n         (spi_ss_n),
        .i_sck          (spi_sck),
        .i_mosi         (spi_mosi),
        .o_miso         (spi_miso),
        .o_miso_oe      (spi_miso_en),
        .o_rx_data      (rx_data),
        .o_rx_data_valid(rx_valid),
        .i_tx_data      (tx_byte),
        .o_tx_data_hold ()
    );

    reg  rx_valid_d;
    wire rx_pulse = rx_valid & ~rx_valid_d;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) rx_valid_d <= 1'b0;
        else        rx_valid_d <= rx_valid;

    // ------------------------------------------------------------------------
    //  NTT core (forward / inverse) - unified butterfly
    // ------------------------------------------------------------------------
    reg         ntt_start, ntt_inv;
    wire        ntt_done, bf_start, bf_done;
    wire [1:0]  bf_mode;
    wire [7:0]  bf_aa, bf_ab, bf_aw;

    ntt_master u_master (
        .clk      (clk),
        .rst      (rst),
        .start    (ntt_start),
        .op_inv   (ntt_inv),
        .done     (ntt_done),
        .bf_start (bf_start),
        .bf_mode  (bf_mode),
        .bf_addr_a(bf_aa),
        .bf_addr_b(bf_ab),
        .bf_addr_w(bf_aw),
        .bf_done  (bf_done)
    );

    wire [7:0]  bf_raddr, bf_waddr, bf_twaddr;
    wire        bf_ren,   bf_wen,   bf_twren;
    wire [15:0] bf_wdata;

    ntt_butterfly u_bf (
        .clk      (clk),
        .rst      (rst),
        .start    (bf_start),
        .mode     (bf_mode),
        .addr_a   (bf_aa),
        .addr_b   (bf_ab),
        .addr_w   (bf_aw),
        .done     (bf_done),
        .mem_raddr(bf_raddr),
        .mem_ren  (bf_ren),
        .mem_rdata(a_rdata),
        .mem_waddr(bf_waddr),
        .mem_wdata(bf_wdata),
        .mem_wen  (bf_wen),
        .tw_addr  (bf_twaddr),
        .tw_ren   (bf_twren),
        .tw_rdata (tw_rdata)
    );

    // ------------------------------------------------------------------------
    //  Basemul core (A (*) B -> A), reuses its own mult/REDC internally
    // ------------------------------------------------------------------------
    reg         bm_start;
    wire        bm_done;
    wire [7:0]  bm_araddr, bm_braddr, bm_zaddr, bm_rwaddr;
    wire        bm_aren,   bm_bren,   bm_zren,  bm_rwen;
    wire [15:0] bm_rwdata;

    basemul u_bmul (
        .clk    (clk),
        .rst    (rst),
        .start  (bm_start),
        .done   (bm_done),
        .a_raddr(bm_araddr),
        .a_ren  (bm_aren),
        .a_rdata(a_rdata),
        .b_raddr(bm_braddr),
        .b_ren  (bm_bren),
        .b_rdata(b_rdata),
        .z_addr (bm_zaddr),
        .z_ren  (bm_zren),
        .z_rdata(tw_rdata),
        .r_waddr(bm_rwaddr),
        .r_wdata(bm_rwdata),
        .r_wen  (bm_rwen)
    );

    // ------------------------------------------------------------------------
    //  Command decoder
    // ------------------------------------------------------------------------
    localparam H_IDLE = 2'd0,
               H_WRA  = 2'd1,   // load operand A
               H_WRB  = 2'd2,   // load operand B
               H_WRZ  = 2'd3;   // load zetas
    // read-back uses a dedicated flag (only 2 bits for hmode)
    reg  [1:0] hmode;
    reg        rdc;             // read-back A active
    reg  [9:0] bptr;
    reg        run;             // NTT active
    reg        bmrun;           // basemul active
    reg        dlatch;          // last op done

    wire [7:0] word_addr = bptr[9:1];
    wire       hi        = bptr[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hmode     <= H_IDLE;
            rdc       <= 1'b0;
            bptr      <= 10'd0;
            run       <= 1'b0;
            bmrun     <= 1'b0;
            dlatch    <= 1'b0;
            ntt_start <= 1'b0;
            ntt_inv   <= 1'b0;
            bm_start  <= 1'b0;
        end else begin
            ntt_start <= 1'b0;
            bm_start  <= 1'b0;

            if (ntt_done) begin dlatch <= 1'b1; run   <= 1'b0; end
            if (bm_done)  begin dlatch <= 1'b1; bmrun <= 1'b0; end

            if (rx_pulse) begin
                if (hmode == H_IDLE && !rdc) begin
                    case (rx_data)
                        8'h10: begin hmode <= H_WRA; bptr <= 10'd0; end
                        8'h11: begin hmode <= H_WRB; bptr <= 10'd0; end
                        8'h20: begin hmode <= H_WRZ; bptr <= 10'd0; end
                        8'h30: begin ntt_start <= 1'b1; ntt_inv <= 1'b0; run   <= 1'b1; dlatch <= 1'b0; end
                        8'h31: begin ntt_start <= 1'b1; ntt_inv <= 1'b1; run   <= 1'b1; dlatch <= 1'b0; end
                        8'h32: begin bm_start  <= 1'b1;                  bmrun <= 1'b1; dlatch <= 1'b0; end
                        8'h50: begin rdc <= 1'b1; bptr <= 10'd0; end
                        default: ; // 0x40 STATUS: tx_byte already reflects dlatch
                    endcase
                end else if (rdc) begin
                    if (bptr == 10'd511) rdc <= 1'b0;
                    bptr <= bptr + 10'd1;
                end else begin
                    // streaming a load (A / B: 512 bytes, Z: 256 bytes)
                    if ((hmode == H_WRZ && bptr == 10'd255) ||
                        (hmode != H_WRZ && bptr == 10'd511)) hmode <= H_IDLE;
                    bptr <= bptr + 10'd1;
                end
            end
        end
    end

    // MISO byte: coeff during read-back, else status
    wire [7:0] rd_byte = hi ? BRAM1_DATA_OUT : BRAM0_DATA_OUT;
    always @(*) tx_byte = rdc ? rd_byte : {7'b0, dlatch};

    // ------------------------------------------------------------------------
    //  BRAM arbitration :  run -> butterfly ,  bmrun -> basemul ,  else -> host
    // ------------------------------------------------------------------------
    wire host_wr_a = (hmode == H_WRA) & rx_pulse;
    wire host_wr_b = (hmode == H_WRB) & rx_pulse;
    wire host_wr_z = (hmode == H_WRZ) & rx_pulse;

    // ---- coeff / A (BRAM0/1) ----
    wire        a_ren   = run   ? bf_ren
                        : bmrun ? bm_aren
                        :         rdc;
    wire [7:0]  a_raddr = run   ? bf_raddr
                        : bmrun ? bm_araddr
                        :         word_addr;
    wire        a0_wen  = run   ? bf_wen
                        : bmrun ? bm_rwen
                        :         (host_wr_a & ~hi);
    wire        a1_wen  = run   ? bf_wen
                        : bmrun ? bm_rwen
                        :         (host_wr_a &  hi);
    wire [7:0]  a_waddr = run   ? bf_waddr
                        : bmrun ? bm_rwaddr
                        :         word_addr;
    wire [7:0]  a0_din  = run   ? bf_wdata[7:0]
                        : bmrun ? bm_rwdata[7:0]
                        :         rx_data;
    wire [7:0]  a1_din  = run   ? bf_wdata[15:8]
                        : bmrun ? bm_rwdata[15:8]
                        :         rx_data;

    // ---- twiddle (BRAM2/3) ----
    wire        t_ren   = run   ? bf_twren
                        : bmrun ? bm_zren
                        :         1'b0;
    wire [7:0]  t_raddr = run   ? bf_twaddr
                        : bmrun ? bm_zaddr
                        :         8'd0;

    // ---- operand B (BRAM4/5) ----
    wire        b_ren   = bmrun ? bm_bren   : 1'b0;
    wire [7:0]  b_raddr = bmrun ? bm_braddr : 8'd0;

    // ========================================================================
    //  BRAM port wiring (enables inverted to active-low at the pads)
    // ========================================================================
    // ---- BRAM0 : A low ----
    assign BRAM0_READ_ADDR  = {1'b0, a_raddr};
    assign BRAM0_REN        = ~a_ren;
    assign BRAM0_RCLKEN     = ~a_ren;
    assign BRAM0_WRITE_ADDR = {1'b0, a_waddr};
    assign BRAM0_DATA_IN    = a0_din;
    assign BRAM0_WEN        = ~a0_wen;
    assign BRAM0_WCLKEN     = ~a0_wen;
    // ---- BRAM1 : A high ----
    assign BRAM1_READ_ADDR  = {1'b0, a_raddr};
    assign BRAM1_REN        = ~a_ren;
    assign BRAM1_RCLKEN     = ~a_ren;
    assign BRAM1_WRITE_ADDR = {1'b0, a_waddr};
    assign BRAM1_DATA_IN    = a1_din;
    assign BRAM1_WEN        = ~a1_wen;
    assign BRAM1_WCLKEN     = ~a1_wen;
    // ---- BRAM2 : twiddle low ----
    assign BRAM2_READ_ADDR  = {1'b0, t_raddr};
    assign BRAM2_REN        = ~t_ren;
    assign BRAM2_RCLKEN     = ~t_ren;
    assign BRAM2_WRITE_ADDR = {1'b0, word_addr};
    assign BRAM2_DATA_IN    = rx_data;
    assign BRAM2_WEN        = ~(host_wr_z & ~hi);
    assign BRAM2_WCLKEN     = ~(host_wr_z & ~hi);
    // ---- BRAM3 : twiddle high ----
    assign BRAM3_READ_ADDR  = {1'b0, t_raddr};
    assign BRAM3_REN        = ~t_ren;
    assign BRAM3_RCLKEN     = ~t_ren;
    assign BRAM3_WRITE_ADDR = {1'b0, word_addr};
    assign BRAM3_DATA_IN    = rx_data;
    assign BRAM3_WEN        = ~(host_wr_z & hi);
    assign BRAM3_WCLKEN     = ~(host_wr_z & hi);
    // ---- BRAM4 : B low ----
    assign BRAM4_READ_ADDR  = {1'b0, b_raddr};
    assign BRAM4_REN        = ~b_ren;
    assign BRAM4_RCLKEN     = ~b_ren;
    assign BRAM4_WRITE_ADDR = {1'b0, word_addr};
    assign BRAM4_DATA_IN    = rx_data;
    assign BRAM4_WEN        = ~(host_wr_b & ~hi);
    assign BRAM4_WCLKEN     = ~(host_wr_b & ~hi);
    // ---- BRAM5 : B high ----
    assign BRAM5_READ_ADDR  = {1'b0, b_raddr};
    assign BRAM5_REN        = ~b_ren;
    assign BRAM5_RCLKEN     = ~b_ren;
    assign BRAM5_WRITE_ADDR = {1'b0, word_addr};
    assign BRAM5_DATA_IN    = rx_data;
    assign BRAM5_WEN        = ~(host_wr_b & hi);
    assign BRAM5_WCLKEN     = ~(host_wr_b & hi);

endmodule