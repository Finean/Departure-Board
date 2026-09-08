`timescale 1ns/1ps
`default_nettype none

import params::*;

module uart_rx
    (
    input wire clk,
    input wire read,
    input wire rx_in,
    output reg [7:0] value,
    output reg par_ok,
    output reg recd
    );
    reg rx1, rx2;
    always @(posedge clk) begin
        rx1 <= rx_in;
        rx2 <= rx1;
    end
    
    reg [15:0] counter;
    reg [3:0] cur_bit;  // 0=start, 1-8=data, 9=parity (even), 10=stop
    reg [7:0] cur_data;
    reg busy;
    reg flag_rst;
    
    initial begin 
        busy = 0;
        flag_rst = 0;
        cur_data = 0;
        par_ok = 0;
        cur_bit = 0;
        counter = 0;
        rx1 = 1;
        rx2 = 1;
        recd = 0;
        value = 0;
    end
    
    always @(posedge clk) begin
        if (read) begin // Use read input to reset recd flag
            recd <= 0;
        end else begin
            if (!busy) begin
                if (~rx2) begin  // Detect start bit
                    busy <= 1;
                    counter <= 0;
                    cur_bit <= 0;
                    cur_data <= 0;
                end
            end else begin
                if (counter == SAMPLE_POINT) begin
                    counter <= counter + 1;
                    
                    case (cur_bit)
                        0: begin
                            if (rx2 != 0) busy <= 0;  // Invalid start
                        end
                        1, 2, 3, 4, 5, 6, 7, 8: begin
                            cur_data <= {rx2, cur_data[1 +: 7]}; // Shift register
                        end
                        9: begin
                            // Fixed parity check for even parity bit
                            par_ok <= (^{cur_data, rx2}) == 1'b0;
                        end
                        10: begin
                            if (rx2 == 1) begin
                                if (par_ok) begin
                                    value <= cur_data; // Latch cur_data into output value, allows rest of device to keep processing old data while new is received
                                    recd <= 1;  // Set recd flag
                                end else begin
                                    value <= cur_data;
                                end
                            end
                        end
                    endcase
                    
                end else if (counter == CYCLES_PER_BIT - 1) begin
                    counter <= 0;
                    if (cur_bit == 10) begin
                        busy <= 0;
                        cur_bit <= 0;
                    end else begin
                        cur_bit <= cur_bit + 1;
                    end
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end
endmodule