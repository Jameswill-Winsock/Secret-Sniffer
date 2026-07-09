// full kyber forward ntt accelerator: RP2040 <-SPI-> FPGA <-> BRAM.
// uses the canonical shrike spi_target (mode 0, MSB, 8-bit). Command decoder streams coeffs/zetas in, runs the ntt, streams results out. 
// bram is arbitrated between the host (load/readback while idle) and the butterfly (during compute).

// instruction set: (one opcode byte, then payload bytes, each byte = one spi exchange):
//   LDC 0x10  LOAD_COEFF : next 512 bytes -> coeff[0..255] as lo,hi,lo,hi...
//   LDZ 0x20  LOAD_ZETA  : next 256 bytes -> zetas[0..127] as lo,hi...
//   STR 0x30  START      : kick the ntt
//   STA 0x40  STATUS     : MISO of following exchange = {7'b0, done}
//   RDC 0x50  READ_COEFF : following 512 exchanges return coeff[0..255] lo,hi...

//   MISO is {7'b0,done} except during READ_COEFF, where it streams coeff bytes.
(* top *) module shrike_ntt_top (
    (* iopad_external_pin, clkbuf_inhibit *) input clk,
    (* iopad_external_pin *) output clk_en,
    (* iopad_external_pin *) input  rst_n,
    // SPI (RP2040 is controller)
    (* iopad_external_pin *) input  spi_ss_n,
    (* iopad_external_pin *) input  spi_sck,
    (* iopad_external_pin *) input  spi_mosi,
    (* iopad_external_pin *) output spi_miso,
    (* iopad_external_pin *) output spi_miso_en,
    // BRAM0/1 = coeff lo/hi byte ; BRAM2/3 = twiddle lo/hi byte  (all RATIO=00, enables active-low)
    (* iopad_external_pin *) output [1:0] BRAM0_RATIO, output [7:0] BRAM0_DATA_IN, output BRAM0_WEN, output BRAM0_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM0_WRITE_ADDR, input [7:0] BRAM0_DATA_OUT, output BRAM0_REN, output BRAM0_RCLKEN, output [8:0] BRAM0_READ_ADDR,
    (* iopad_external_pin *) output [1:0] BRAM1_RATIO, output [7:0] BRAM1_DATA_IN, output BRAM1_WEN, output BRAM1_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM1_WRITE_ADDR, input [7:0] BRAM1_DATA_OUT, output BRAM1_REN, output BRAM1_RCLKEN, output [8:0] BRAM1_READ_ADDR,
    (* iopad_external_pin *) output [1:0] BRAM2_RATIO, output [7:0] BRAM2_DATA_IN, output BRAM2_WEN, output BRAM2_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM2_WRITE_ADDR, input [7:0] BRAM2_DATA_OUT, output BRAM2_REN, output BRAM2_RCLKEN, output [8:0] BRAM2_READ_ADDR,
    (* iopad_external_pin *) output [1:0] BRAM3_RATIO, output [7:0] BRAM3_DATA_IN, output BRAM3_WEN, output BRAM3_WCLKEN,
    (* iopad_external_pin *) output [8:0] BRAM3_WRITE_ADDR, input [7:0] BRAM3_DATA_OUT, output BRAM3_REN, output BRAM3_RCLKEN, output [8:0] BRAM3_READ_ADDR
);
    assign clk_en = 1'b1;
    wire rst = ~rst_n;
    assign BRAM0_RATIO=2'b00; assign BRAM1_RATIO=2'b00; assign BRAM2_RATIO=2'b00; assign BRAM3_RATIO=2'b00;

    // ---------------- SPI target ----------------
    wire [7:0] rx_data; wire rx_valid; reg [7:0] tx_byte;
    spi_target #(
        .CPOL(0),
        .CPHA(0),
        .WIDTH(8),
        .LSB(0)) 
        u_spi (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_enable(1'b1),

        .i_ss_n(spi_ss_n),
        .i_sck(spi_sck),
        .i_mosi(spi_mosi),

        .o_miso(spi_miso),
        .o_miso_oe(spi_miso_en),

        .o_rx_data(rx_data),
        .o_rx_data_valid(rx_valid),

        .i_tx_data(tx_byte),
        .o_tx_data_hold());
    
    // one-cycle rx pulse
    reg rx_valid_d; 
    wire rx_pulse = rx_valid & ~rx_valid_d;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rx_valid_d<=0; 
        end else begin 
            rx_valid_d<=rx_valid;
        end
    end

    // ntt core
    wire bf_start;
    wire bf_done; 
    wire ntt_done;

    wire [7:0] ba, bb, bw;
    reg  ntt_start;

    ntt_master u_master(
        .clk(clk),
        .rst(rst),
        .start(ntt_start),
        .done(ntt_done),
        .bf_start(bf_start),

        .bf_addr_a(ba),
        .bf_addr_b(bb),
        .bf_addr_w(bw),
        .bf_done(bf_done));

    wire [7:0] bf_raddr, bf_waddr, bf_twaddr; 
    wire bf_ren, bf_wen, bf_twren; 
    wire [15:0] bf_wdata;

    wire [15:0] coeff_rdata = {BRAM1_DATA_OUT, BRAM0_DATA_OUT};
    wire [15:0] tw_rdata    = {BRAM3_DATA_OUT, BRAM2_DATA_OUT};
    
    ntt_butterfly u_bf(
        .clk(clk),
        .rst(rst),
        .start(bf_start),
        .addr_a(ba),
        .addr_b(bb),
        .addr_w(bw),
        .done(bf_done),

        .mem_raddr(bf_raddr),
        .mem_ren(bf_ren),
        .mem_rdata(coeff_rdata),

        .mem_waddr(bf_waddr),
        .mem_wdata(bf_wdata),
        .mem_wen(bf_wen),

        .tw_addr(bf_twaddr),
        .tw_ren(bf_twren),
        .tw_rdata(tw_rdata
        ));

    // instruction decoder
    localparam H_IDLE=2'd0, H_WRC=2'd1, H_WRZ=2'd2, H_RDC=2'd3;

    reg [1:0] hmode; 
    reg [9:0] bptr; 
    reg run, dlatch;
    wire [7:0] word_addr = bptr[9:1];       // byte pair -> word index
    wire       hi        = bptr[0];         // 0=low byte, 1=high byte

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin hmode<=H_IDLE; bptr<=0; run<=0; dlatch<=0; ntt_start<=0; end
        else begin
            ntt_start<=0;
            if (ntt_done) begin dlatch<=1; run<=0; end
            if (rx_pulse) begin
                case (hmode)
                    H_IDLE: case (rx_data)
                        8'h10: begin hmode<=H_WRC; bptr<=0; end
                        8'h20: begin hmode<=H_WRZ; bptr<=0; end
                        8'h30: begin ntt_start<=1; run<=1; dlatch<=0; end
                        8'h50: begin hmode<=H_RDC; bptr<=0; end
                        default: ; // 0x40 status: tx_byte already reflects dlatch
                    endcase

                    H_WRC: begin 
                        if (bptr==10'd511) hmode<=H_IDLE; bptr<=bptr+1; 
                    end
                    H_WRZ: begin 
                        if (bptr==10'd255) hmode<=H_IDLE; bptr<=bptr+1; 
                    end
                    H_RDC: begin 
                        if (bptr==10'd511) hmode<=H_IDLE; bptr<=bptr+1; 
                    end
                endcase
            end
        end
    end

    // host readback byte (coeff lo/hi selected by bptr[0])
    wire [7:0] rd_byte = hi ? BRAM1_DATA_OUT : BRAM0_DATA_OUT;
    always @(*) begin 
        tx_byte = (hmode==H_RDC) ? rd_byte : {7'b0, dlatch};
    end

    // BRAM arbitration (run -> butterfly, else -> host) ----------------
    // coeff read
    wire        c_ren   = run ? bf_ren  : (hmode==H_RDC);
    wire [7:0]  c_raddr = run ? bf_raddr : word_addr;
    // coeff write: compute -> both lanes 16-bit; host -> one lane per byte
    wire        cw_h    = (hmode==H_WRC) & rx_pulse;
    wire        c0_wen  = run ? bf_wen : (cw_h & ~hi);
    wire        c1_wen  = run ? bf_wen : (cw_h &  hi);
    wire [7:0]  c_waddr = run ? bf_waddr : word_addr;
    wire [7:0]  c0_din  = run ? bf_wdata[7:0]  : rx_data;
    wire [7:0]  c1_din  = run ? bf_wdata[15:8] : rx_data;
    // twiddle read (compute) / write (host zeta load)
    wire        t_ren   = run ? bf_twren : 1'b0;
    wire [7:0]  t_raddr = run ? bf_twaddr : 8'd0;
    wire        tw_h    = (hmode==H_WRZ) & rx_pulse;
    wire        t2_wen  = tw_h & ~hi;
    wire        t3_wen  = tw_h &  hi;
    wire [7:0]  t_waddr = word_addr;

    // ---- BRAM0 (coeff lo) ----
    assign BRAM0_READ_ADDR={1'b0,c_raddr}; 
    assign BRAM0_REN=~c_ren; 
    assign BRAM0_RCLKEN=~c_ren;

    assign BRAM0_WRITE_ADDR={1'b0,c_waddr}; 
    assign BRAM0_DATA_IN=c0_din; 
    assign BRAM0_WEN=~c0_wen; 
    assign BRAM0_WCLKEN=~c0_wen;
    
    // ---- BRAM1 (coeff hi) ----
    assign BRAM1_READ_ADDR={1'b0,c_raddr}; 
    assign BRAM1_REN=~c_ren; 
    assign BRAM1_RCLKEN=~c_ren;

    assign BRAM1_WRITE_ADDR={1'b0,c_waddr}; 
    assign BRAM1_DATA_IN=c1_din; 
    assign BRAM1_WEN=~c1_wen; 
    assign BRAM1_WCLKEN=~c1_wen;

    // ---- BRAM2 (twiddle lo) ----
    assign BRAM2_READ_ADDR={1'b0,t_raddr}; 
    assign BRAM2_REN=~t_ren; 
    assign BRAM2_RCLKEN=~t_ren;

    assign BRAM2_WRITE_ADDR={1'b0,t_waddr}; 
    assign BRAM2_DATA_IN=rx_data; 
    assign BRAM2_WEN=~t2_wen; 
    assign BRAM2_WCLKEN=~t2_wen;

    // ---- BRAM3 (twiddle hi) ----
    assign BRAM3_READ_ADDR={1'b0,t_raddr}; 
    assign BRAM3_REN=~t_ren; 
    assign BRAM3_RCLKEN=~t_ren;

    assign BRAM3_WRITE_ADDR={1'b0,t_waddr}; 
    assign BRAM3_DATA_IN=rx_data; 
    assign BRAM3_WEN=~t3_wen; 
    assign BRAM3_WCLKEN=~t3_wen;

endmodule
