`timescale 1ns/1ps
`default_nettype none

import params::*;
import font::*;

module textcontroller(
        input wire sysclk,
        input wire reset,
        input wire [7:0] uart_val,
        input wire uart_recd,
        input wire buf_ready,
        output reg uart_rst,
        output reg [15:0] wrt_col,
        output reg [5:0] wrt_row,
        output reg out_data,
        output reg write,
        output reg [9:0] max_scroll,
        output reg switch_buf,

        output reg head_double,
        output reg mid_double,
        output reg [1:0][1:0] low_info,
        output reg [3:0] brightness,
        output reg [2:0][7:0] led_colour
    );
    
    // Where to start (x, y), width of area (dx)
    
    // 0-8 HEAD, 9-10 br, 11-28 MID, 29-30 br, 31 - 48 LOW
    // UART Commands:
    // clear 00
    // update display FF    
    // brightess: 1X (Last 3 bits of X determine brightness)
    // led_colour: 20;
    
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

        cur_char <= cur_char_ascii > 31 ? (cur_char_ascii < 123 ? brom_reg : 0) : 0;
    end

    
    reg [7:0] state;
    reg [7:0] cur_head;
    reg [199:0][7:0] cur_data [0:10];   
    
    reg [3:0] cur_line;
    reg [199:0][7:0] in_buffer; 
    
    reg [3:0] char_x;
    reg [3:0] char_y;
    
    reg [3:0] cur_row;
    reg [7:0] cur_col;

    wire [4:0] cur_width;
    wire [3:0] cur_offset;
    
    reg [2:0] cyclehold;
    
    reg head_double_tmp;
    reg mid_double_tmp;
    reg [1:0][1:0] low_info_tmp;
    reg [9:0] max_scroll_tmp;
    
    reg [2:0][7:0] led_colour_tmp;
    reg [3:0] counter;
    
    reg [15:0] timeout_counter;
    
    assign font_addr = cur_data[cur_row][cur_col];
    assign cur_width = cur_char[5][4 +: 5];
    assign cur_offset = cur_char[5][0 +: 4];
        
    `ifdef SYNTHESIS
        initial begin
            brightness = 3'b011;
            led_colour = '{8'h00, 8'h40, 8'hFF};
            timeout_counter = 0;
            write = 0;
            switch_buf = 0;
            max_scroll = 0;
            head_double = 0;
            mid_double = 0;
            low_info = '{2'b00, 2'b00};
            for (int i = 0; i < 11; i = i + 1) begin
                cur_data[i] = '{default: 8'hFF};
            end
        end
    `endif

    integer i;

    logic new_uart_msg;
    assign new_uart_msg = uart_recd && !uart_rst;

    localparam [7:0] WAIT_RECV = 0;
    localparam [7:0] DECODE_MSG = 1;
    localparam [7:0] LISTEN_MSG = 2;
    localparam [7:0] WRITE_TEXT = 3;
    localparam [7:0] CLEAR_BUFFER = 4;
    localparam [7:0] TEXT_COLOUR = 5;

    always_ff @(posedge sysclk) begin
        if (reset) begin
            state = 4;
        end else begin
            case (state)
                WAIT_RECV: begin
                    if (new_uart_msg) begin
                        state <= DECODE_MSG;
                    end
                end
                DECODE_MSG: begin
                    casez (cur_head)
                        8'h00: state <= WAIT_RECV;
                        8'hFF: state <= CLEAR_BUFFER;
                        8'hA1, 8'hA2, 8'hA3, 8'hB4, 8'hB5, 8'hC6, 8'hC7, 8'hC8, 8'hC9, 8'hCA, 8'hCB: begin
                            state <= LISTEN_MSG;
                        end
                        8'h1Z: state <= WAIT_RECV;
                        8'h20: state <= TEXT_COLOUR;
                        default: state <= WAIT_RECV;
                    endcase
                end
                LISTEN_MSG: begin
                    if (new_uart_msg && uart_val == 8'h00) begin
                        state <= WAIT_RECV;
                    end
                end
                WRITE_TEXT: begin
                    if (cur_row == 11 && buf_ready) begin
                        state <= WAIT_RECV;
                    end
                end
                CLEAR_BUFFER: begin
                    if (wrt_col == BUFFER_WIDTH - 1) begin
                        state <= WRITE_TEXT;
                    end
                end
                TEXT_COLOUR: begin
                    if (counter >= 3 && buf_ready) begin
                        state <= WAIT_RECV;
                    end
                end
                default: state <= WAIT_RECV;
            endcase
        end

        uart_rst <= 0;
        write <= 0;

        case (state)
            WAIT_RECV: begin // Listen for header
                if (new_uart_msg) begin
                    cur_head <= uart_val;
                    uart_rst <= 1;
                end
            end
            DECODE_MSG: begin // Parse received header
                casez (cur_head)
                    8'h00: begin
                        for (i = 0; i < 11; i = i + 1) begin
                            cur_data[i][0] <= 8'hFF;
                        end
                    end
                    8'hFF: begin
                        cur_col <= 0;
                        cur_row <= 0;
                        cyclehold <= 3'b111;
                        wrt_col <= 0;
                        wrt_row <= 0;
                        out_data <= 0;
                        write <= 1;
                        head_double_tmp <= 1;
                        mid_double_tmp <= 1;
                        low_info_tmp <= '{2'b11, 2'b11};
                        max_scroll_tmp <= 0;
                    end
                    8'hA1, 8'hA2, 8'hA3, 8'hB4, 8'hB5, 8'hC6, 8'hC7, 8'hC8, 8'hC9, 8'hCA, 8'hCB: begin
                        cur_line <= cur_head[0 +: 4] - 1;
                    end
                    8'h1Z: begin
                        brightness <= cur_head[0 +: 3];
                    end
                    8'h20: begin
                        counter <= 0;
                    end
                    default: ;
                endcase
            end
            LISTEN_MSG: begin // Listen for input
                if (new_uart_msg) begin
                    if (uart_val == 8'h00) begin
                        cur_data[cur_line] <= in_buffer;
                    end else begin
                        in_buffer <= {in_buffer[0 +: 120], uart_val};
                    end
                    uart_rst <= 1;
                end
            end
            WRITE_TEXT: begin // Write to image buffer, then switch
                write <= 0;
                if (cur_row == 11) begin // Switch
                    if (buf_ready) begin
                        head_double <= head_double_tmp;
                        mid_double <= mid_double_tmp;
                        low_info <= low_info_tmp;
                        max_scroll <= max_scroll_tmp;
                        switch_buf <= !switch_buf;
                        state <= 0;
                    end
                end else if (font_addr == 8'hFF || cur_col >= 200) begin
                    if (cur_col == 0) begin
                        case (cur_row) 
                            1: head_double_tmp <= 0;
                            4: mid_double_tmp <= 0;
                            5: low_info_tmp[0][0] <= 0;
                            6: low_info_tmp[0][1] <= 0;
                            8: low_info_tmp[1][0] <= 0;
                            9: low_info_tmp[1][1] <= 0;
                            default: ;
                        endcase
                    end
                    case (cur_row) // Set wrt_col
                        0: wrt_col <= WIDTH + 1;
                        1: wrt_col <= WIDTH - 43;
                        2: wrt_col <= 1;
                        3: begin
                            wrt_col <= 1;
                            if (wrt_col > WIDTH) begin
                                max_scroll_tmp <= wrt_col + 96;
                            end else begin
                                max_scroll_tmp <= 0;
                            end
                        end
                        4: wrt_col <= 1;
                        5: wrt_col <= WIDTH + 1;
                        6: wrt_col <= WIDTH - 43;
                        7: wrt_col <= 1;
                        8: wrt_col <= WIDTH + 1;
                        9: wrt_col <= WIDTH - 43;
                        default: wrt_col <= 1;
                    endcase
                    cyclehold <= 3'b111;
                    cur_row <= cur_row + 1;
                    cur_col <= 0;
                    char_x <= 0;
                    char_y <= 0;
                end else if (cyclehold[2]) begin
                    case (cur_row) // Set wrt_row
                        0, 1, 2:   wrt_row <= 0;
                        3:         wrt_row <= 11;
                        4:         wrt_row <= 20;
                        5, 6, 7:   wrt_row <= 31;
                        8, 9, 10:  wrt_row <= 40;
                        default:   wrt_row <= 0;
                    endcase
                    if (cur_col > 0) begin
                        wrt_col <= wrt_col - cur_offset;
                    end
                    char_x <= 0;
                    char_y <= 1;
                    if (cur_width == 0) begin
                        wrt_col <= wrt_col + 1;
                        cur_col <= cur_col + 1;
                    end else begin
                        write <= cur_char[4][8];
                        out_data <= cur_char[4][8];
                        cyclehold <= {cyclehold[0+:2], 1'b0};
                    end
                end else begin
                    out_data <= cur_char[4 - char_x][8 - char_y];
                    wrt_row <= wrt_row + 1;
                    char_y <= char_y + 1;
                    write <= cur_char[4 - char_x][8 - char_y];
                    if (char_y == 0) begin
                        wrt_col <= wrt_col + 1;
                        wrt_row <= wrt_row - 8;
                    end else if (char_y == 8) begin
                        if (char_x == cur_width - 1) begin // Next char
                            cyclehold <= 1;
                            cur_col <= cur_col + 1;
                            wrt_col <= wrt_col + 2;
                        end else begin
                            char_y <= 0;
                            char_x <= char_x + 1;
                        end
                    end
                end
            end
            CLEAR_BUFFER: begin // Clear image buffer
                out_data <= 0;
                write <= 1;
                if (wrt_col == BUFFER_WIDTH - 1) begin
                    wrt_col <= 1;
                    wrt_row <= 0;
                    write <= 0;
                end else if (wrt_row == 49) begin
                    wrt_col <= wrt_col + 1;
                    wrt_row <= 0;
                end else begin
                    wrt_row <= wrt_row + 1;
                end
            end
            TEXT_COLOUR: begin
                if (counter >= 3) begin
                    if (buf_ready) begin
                        led_colour <= led_colour_tmp;
                        counter <= 0;
                        state <= 0;
                    end
                end else if (new_uart_msg) begin
                    led_colour_tmp[counter] <= uart_val;
                    counter <= counter + 1;
                    uart_rst <= 1;
                end
            end
            default: ;
        endcase
    end 
endmodule
