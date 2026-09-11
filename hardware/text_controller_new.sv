`timescale 1ns/1ps
`default_nettype none

import params::*;

module text_controller_new (
    input wire sysclk,
    input wire reset,

    input wire [3:0] operation,
    input wire [7:0] op_data,
    input wire op_valid,
    output logic op_ready,

    input wire buffer_ready,
    output logic buffer_select,
    output logic [15:0] wrt_col,
    output logic [5:0] wrt_row,
    output logic buf_din,
    output logic buf_wen,

    output logic [9:0] max_scroll,
    output logic head_double,
    output logic mid_double,
    output logic [1:0][1:0] low_info,
    output logic [3:0] brightness,
    output logic [2:0][7:0] led_colour
    );

    // font_table block ROM
    (* rom_style = "block" *) reg [5:0][8:0] font_table [0:90];

    `ifdef SYNTHESIS
        font_table = FONT_LIB;
    `endif

    logic [7:0] font_addr, cur_char_ascii;
    logic [5:0][8:0] brom_reg, cur_char;

    always_ff @(posedge sysclk) begin
        brom_reg <= font_table[font_addr - 32];
        cur_char_ascii <= font_addr;

        cur_char <= cur_char_ascii > 31 ? (cur_char_ascii < 123 ? brom_reg : '{6{0}}) : '{6{0}};
    end

    logic [7:0] state;

    localparam [7:0] WAIT_OP = 0;
    localparam [7:0] DECD_OP = 1;
    localparam [7:0] WAIT_CYCLE = 2;
    localparam [7:0] DRAW_CHAR = 3;
    localparam [7:0] CLEAR_BUF = 4;

    logic [3:0] op;
    logic [7:0] data;

    assign font_addr = data;

    // store number of characters on each row
    logic [3:0] row_number;
    logic [7:0] row_pixels [15:0];
    logic [2:0] rgb_pointer;

    always @(posedge sysclk) begin
        if (reset) begin
            state <= 0;
            buffer_select <= 0;
            op <= 0;
            data <= 0;
            row_number <= 0;
            row_pixels <= '{16{0}};
            rgb_pointer <= 0;
        end else begin
            if (rgb_pointer == 3) begin
                rgb_pointer <= 0;
            end


            case (state)
                WAIT_OP: begin
                    op_ready <= 1'b1;
                    if (op_ready && op_valid) begin
                        op <= operation;
                        data <= op_data;
                        state <= DECD_OP;
                        op_ready <= 1'b0;
                    end
                end
                DECD_OP: begin
                    case(op)
                        0: begin
                            row_pixels <= '{16{0}};
                            state <= CLEAR_BUF;
                        end
                        1: begin
                            if (buffer_ready) begin
                                buffer_select <= !buffer_select;
                                state <= WAIT_OP;
                            end
                        end
                        2: begin
                            brightness = data[3:0];
                            state <= WAIT_OP;
                        end
                        3: begin
                            led_colour[rgb_pointer] <= data;
                            rgb_pointer <= rgb_pointer + 1;
                            state <= WAIT_OP;
                        end
                        4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14: begin
                            row_number <= op - 4;
                            state <= DRAW_CHAR;
                        end
                        default: state <= WAIT_OP;
                    endcase
                end
                WAIT_CYCLE: begin
                    // delay by 1 cycle for BROM read
                    state <= DRAW_CHAR;
                end
                DRAW_CHAR: begin
                    

                end
                CLEAR_BUF: ;


                default: state <= WAIT_OP;
            endcase


        end





    end




endmodule
