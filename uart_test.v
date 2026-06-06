module uart_tx (
    input clk,
    input rst,
    output tx;
);

parameter CLK_FREQ = 27_000_000 ;
parameter BAUD_RATE = 115_200 ;
parameter BAUD_DIV  = CLK_FREQ/BAUD_RATE; //count clock cycles to time each uart bit

reg [7:0] msg [0:6];
initial begin
    msg[0] = 8'h48;
    msg[1] = 8'h45;
    msg[2] = 8'h4C;
    msg[3] = 8'h4C;
    msg[4] = 8'h4F;
    msg[5] = 8'h40D;
    msg[6] = 8'h40A;

end

reg [7:0] shift_reg;
reg[3:0] bit_cnt;
reg [8:0] baud_cnt;
reg [2:0] msg_idx;
reg tx_line;
reg busy_flag;
reg [23:0] gap_cnt;
reg gap_active_flag;
assign tx = tx_line;

//main fsm below
//states are idle (load next byte and begin transmit, or wait for next message transmission), byte transmit, and gap between message (waiting for next counter after next n clock cycles)
always@(posedge clk or negedge rst)begin
    if(!rst) begin
        //reset everything to known idle state
        tx_line <= 1'b1;
        bit_cnt <= 0;
        baud_cnt <= 0;
        msg_idx <= 0;
        busy_flag <= 0;
        gap_cnt <= 0;
        gap_active_flag <= 0;
        shift_reg <= 0;
    end
    else begin
        //idle - load next byte and begin transmit
        if (!busy_flag && !gap_active) begin
            shift_reg <= msg[msg_idx];
            bit_cnt <= 0;
            baud_cnt <= 0;
            busy_flag <= 1;
            tx_line <= 1'b0; //pull tx low for start bit
        end
    else if (busy_flag) begin
        //transmit - send bit one by one and last each bit for BAUD_DIV clock cycles
        if (baud_cnt < BAUD_DIV - 1) begin
            //wait as still counting clock cycles for current bit and advance by 1
            baud_cnt <= baud_cnt + 1;
        end
        else begin
            //current bit finished move to next
            baud_cnt <= 0;
            bit_cnt <= bit_cnt+1;
            if (bit_cnt<8)begin
                //send next data bit lsb
                tx_line <= shift_reg[0];
                shift_reg <= shift_reg>>1;
            end
            else begin
                //if all 8 data bits sent send stop bit i.e. tx high
                tx_reg <= 1'b1;
                busy_flag <=0;

                if (msg_idx == 6) begin
                    //newline char sent begin gap
                    msg_idx <= 0;
                    gap_active_flag <= 1;
                    gap_cnt <= 0;
                end
                else begin
                    //more chars are there move to next char
                    msg_idx <= msg_idx + 1;
                end
            end 
        end
    end
    end
end