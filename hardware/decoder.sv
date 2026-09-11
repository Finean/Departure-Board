`timescale 1ns/1ps
`default_nettype none

import params::*;

// decode message from interface, communicate decoded values to textcontroller
module decoder (
    input wire sysclk,
    input wire reset,
    input wire [7:0] interface_val,
    input wire interface_valid,
    output logic interface_ready,

    output logic [3:0] operation,
    output logic [7:0] op_data,
    output logic op_valid,
    input wire op_ready    
    );

    // Commands:
    // clear 01
    // update display FF    
    // brightess: 1X (Last 4 bits of X determine brightness)
    // led_colour: 20 (3 packets of 8 bits)
    
    // (Start with 0xFF, send text backwards, end with 0x00)
    
    // 0 headname A1 -> cur_data[0]
    // 1 headname2 A2
    // 2 head etd A3
    // 3 mid1 B4
    // 4 mid2 B5
    // 5 lowname11 C6 
    // 6 lowname12 C7
    // 7 low etd1 C8
    // 8 lowname21 C9
    // 9 lowname22 CA
    // 10 low etd2 CB -> cur_data[10];
    // each character is 8 bits, 8'h00 used to mark end of text transfer

    logic [3:0] state;

    localparam [3:0] WAIT_HEADER = 0;
    localparam [3:0] DECD_HEADER = 1;
    localparam [3:0] WAIT_BODY = 3;
    localparam [3:0] DECD_BODY = 4;

    logic [7:0] recd_reg;
    logic [7:0] counter;

    always @(posedge sysclk) begin
        if (reset) begin
            state <= WAIT_HEADER;
            interface_ready <= 1'b0;
            op_valid <= 1'b0;
            counter <= 0;
        end else begin
            if (op_valid && op_ready) begin
                op_valid <= 1'b0;
            end

            case (state) 
                WAIT_HEADER: begin
                    interface_ready <= 1'b1;
                    if (interface_valid && interface_ready) begin
                        recd_reg <= interface_val;
                        interface_ready <= 1'b0;
                        state <= DECD_HEADER;
                    end
                end
                DECD_HEADER: begin
                    casez (recd_reg)
                        8'h01: begin // clear text buffer
                            operation <= 0;
                            op_valid <= 1'b1;
                            state <= WAIT_HEADER;
                        end
                        8'hFF: begin // update display
                            operation <= 1;
                            state <= WAIT_HEADER;
                        end
                        8'h1Z: begin // set brightness
                            operation <= 2;
                            op_valid <= 1'b1;
                            op_data <= {4'h0, recd_reg[3:0]};
                            state <= WAIT_HEADER;
                        end
                        8'h20: begin // set text colour
                            operation <= 3;
                            op_valid <= 1'b0;
                            counter <= 0;
                            state <= WAIT_BODY;
                        end
                        8'hA1, 8'hA2, 8'hA3, 8'hB4, 8'hB5, 8'hC6, 8'hC7, 8'hC8, 8'hC9, 8'hCA, 8'hCB: begin // set text
                            operation <= recd_reg[3:0] + 3;
                            op_valid <= 1'b1;
                            state <= WAIT_BODY;
                        end 
                        default: state <= WAIT_HEADER;
                    endcase
                end
                WAIT_BODY: begin
                    interface_ready <= !op_valid;
                    if (interface_valid && interface_ready) begin
                        recd_reg <= interface_val;
                        interface_ready <= 1'b0;
                        state <= DECD_BODY;
                    end
                end
                DECD_BODY: begin
                    state <= WAIT_BODY;
                    if (operation == 3) begin
                        counter <= counter + 1;
                        op_data <= recd_reg;
                        op_valid <= 1'b1;
                        if (counter == 2) begin
                            state <= WAIT_HEADER;
                        end
                    end else begin
                        if (recd_reg == 8'h00) begin
                            state <= WAIT_HEADER;
                        end else begin
                            op_data <= recd_reg;
                            op_valid <= 1'b1;
                        end
                    end
                end
                default: state <= WAIT_HEADER;
            endcase
        end
    end



endmodule
