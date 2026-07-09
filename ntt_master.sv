// ntt_master - sequences the ct dit butterfly over 7 layers x 128 butterflies
// (kyber n=256 forward ntt). 
// uses ntt_addr_gen for the coefficient/twiddle addresses.
// typical natural order input, bit reversed output (paired with a gs dif (gentleman-sande with decimation in frequency) inverse -> no permute).

module ntt_master #(
    parameter layers = 7,
    parameter bflys  = 128
)(
    input             clk,
    input             rst,
    input             start,
    output reg        done,
    output reg        bf_start,
    output reg [7:0]  bf_addr_a,
    output reg [7:0]  bf_addr_b,
    output reg [7:0]  bf_addr_w,
    input             bf_done
);

  localparam m_idle  = 3'd0, 
             m_issue = 3'd1, 
             m_wait  = 3'd2, 
             m_next  = 3'd3, 
             m_done  = 3'd4;

  reg [2:0] mstate;
  reg [2:0] layer;
  reg [6:0] bidx;

  wire [7:0] a_i;
  wire [7:0] b_i;
  wire [7:0] w_i;

  ntt_addr_gen u_addr (
    .layer (layer), 
    .bf    (bidx), 
    .a_addr(a_i), 
    .b_addr(b_i), 
    .tw_idx(w_i)
  );

  always @(posedge clk) begin
    if (rst) begin
      mstate    <= m_idle; 
      done      <= 1'b0; 
      bf_start  <= 1'b0; 
      layer     <= 3'd0; 
      bidx      <= 7'd0;
      bf_addr_a <= 8'd0;
      bf_addr_b <= 8'd0;
      bf_addr_w <= 8'd0;
    end else begin
      bf_start <= 1'b0; 
      done     <= 1'b0;
      
      case (mstate)
        m_idle: begin
          if (start) begin 
            layer  <= 3'd0; 
            bidx   <= 7'd0; 
            mstate <= m_issue; 
          end
        end

        m_issue: begin
          bf_addr_a <= a_i; 
          bf_addr_b <= b_i; 
          bf_addr_w <= w_i;
          bf_start  <= 1'b1;
          mstate    <= m_wait;
        end

        m_wait: begin
          if (bf_done) begin
            mstate <= m_next;
          end
        end

        m_next: begin
          if (bidx == bflys - 1) begin
            bidx <= 7'd0;
            if (layer == layers - 1) begin
              mstate <= m_done;
            end else begin 
              layer  <= layer + 1; 
              mstate <= m_issue; 
            end
          end else begin 
            bidx   <= bidx + 1; 
            mstate <= m_issue; 
          end
        end

        m_done: begin 
          done   <= 1'b1; 
          mstate <= m_idle; 
        end

        default: begin
          mstate <= m_idle;
        end
      endcase
    end
  end

endmodule
