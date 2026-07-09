//ntt butterfly using cooley tukey and decimation in time
//routes one butterfly's data between coefficient memory and the math blocks:
//read b, read twiddle w -> multiply (b*w) -> redc -> t = b*w mod q
//read a -> a' = (a+t) mod q  (write to addr_a),  b' = (a-t) mod q  (write to addr_b)

//1.    ct dit butterfly: a'=(a+t)mod q, b'=(a-t)mod q, t=b*w mod q.
//2.    twiddles will be in seperate rom, pre-stored in montgomery form (w_mont=w*R mod q); 
//      plain b*w_mont then redc gives b*w mod q. coefficients kept in normal form.
//3.    coefficient memory = 1 read port + 1 write port (real SLG47910 slice-pair),
//      registered read: rdata valid 1 cycle after (raddr,ren). a and b read sequentially.
//      enables active high here; wrapper wraps to nREN/nWEN
//4.    uses one shared alu, time mux'd across the two write blocks to save on one han carlson unit


module ntt_butterfly (
    input clk,
    input rst,
    input start,
    input [7:0] addr_a,
    input [7:0] addr_b,
    input [7:0] addr_w,
    output done,

    //coefficient memory interface
    output reg [7:0] mem_raddr,
    output reg mem_ren,
    input [15:0] mem_rdata,
    output reg [7:0] mem_waddr,
    output reg [15:0] mem_wdata,
    output reg mem_wen,
    
    //twiddle rom interface
    output reg [7:0] tw_addr,
    output reg tw_ren,
    input [15:0] tw_rdata
);

//state machine parameters
localparam idle = 4'd0;
localparam present_b = 4'd1;
localparam cap_b_mul = 4'd2;
localparam cap_a = 4'd3;
localparam wait_mul = 4'd4;
localparam wait_redc = 4'd5;
localparam wr_a = 4'd6;
localparam wr_b = 4'd7;
localparam fin = 4'd8;

reg [3:0] state;
reg [7:0] a_addr_r;
reg [7:0] b_addr_r;
reg [7:0] w_addr_r;
reg [15:0] a_reg;
reg [15:0] t_reg;


//math block interconnects
wire mul_done;
wire [23:0] mul_prod;
reg mul_start;
reg [11:0] mul_a;
reg [11:0] mul_b;

wire redc_done;
wire [15:0] redc_res;
reg redc_start;
reg [23:0] redc_tin;

reg alu_op;
wire [15:0] alu_res;

//module instantiation
mod_mult u_mul (
    .clk(clk),
    .rst(rst),
    .start(mul_start),
    .a(mul_a),
    .b(mul_b),
    .done(mul_done),
    .prod(mul_prod)
);

mont_redc u_redc (
    .clk(clk),
    .rst(rst),
    .start(redc_start),
    .t_in(redc_tin),
    .res_out(redc_res),
    .done(redc_done)
);

alu u_alu (
    .a(a_reg),
    .b(t_reg),
    .op(alu_op),
    .res(alu_res)
);

assign done = (state==fin);

//state and data latches
always @(posedge clk) begin
    if(rst) begin
        state <= idle;
    end else begin
        case(state)
            idle: begin
                if(start) begin
                    a_addr_r <= addr_a;
                    b_addr_r <= addr_b;
                    w_addr_r <= addr_w;
                    state <= present_b;
                end
            end

            present_b: begin
                state <= cap_b_mul;
            end

            cap_b_mul: begin
                state <= cap_a;
            end

            cap_a: begin
                a_reg <= mem_rdata;     // a is finished fetching here
                state <= wait_mul;
            end

            wait_mul: begin
                if(mul_done) begin
                    state <= wait_redc;
                end
            end

            wait_redc: begin
                if(redc_done) begin
                    t_reg <= redc_res;
                    state <= wr_a;
                end
            end

            wr_a: begin
                state <= wr_b;
            end

            wr_b: begin
                state <= fin;
            end

            fin: begin
                state <= idle;
            end

            default: begin
                state <= idle;
            end
        endcase
    end
end

always @(*) begin
    //default assignments to avoid implicit latching
    mem_raddr  = 8'd0; 
    mem_ren    = 1'b0; 
    mem_waddr  = 8'd0; 
    mem_wdata  = 16'd0; 
    mem_wen    = 1'b0;
    tw_addr    = 8'd0; 
    tw_ren     = 1'b0; 
    mul_start  = 1'b0; 
    redc_start = 1'b0; 
    alu_op     = 1'b0;
    mul_a      = 12'd0; 
    mul_b      = 12'd0; 
    redc_tin   = 24'd0;

    case(state)
        present_b: begin
            mem_raddr = b_addr_r;
            mem_ren = 1'b1;
            tw_addr = w_addr_r;
            tw_ren = 1'b1;
        end

        // b and w valid, then latch into multiplier (comb operands) + launch read of a
        cap_b_mul: begin
            mul_a = mem_rdata[11:0];    // call up b
            mul_b = tw_rdata[11:0];     // call up w
            mul_start = 1'b1;           // spin up multiplier interface
            mem_raddr = a_addr_r;       // simultaneously, while multiplier is starting, request a to keep system busy
            mem_ren = 1'b1;
        end

        wait_mul: begin
            if (mul_done) begin
                redc_tin = mul_prod;
                redc_start = 1'b1;
            end
        end

        wr_a: begin
            alu_op = 1'b0;
            mem_waddr = a_addr_r;
            mem_wdata = alu_res;
            mem_wen = 1'b1;
        end //a' = a + t

        wr_b: begin
            alu_op = 1'b1;
            mem_waddr = b_addr_r;
            mem_wdata = alu_res;
            mem_wen = 1'b1;
        end // b' = a - t

        default: ;
    endcase
end

endmodule


