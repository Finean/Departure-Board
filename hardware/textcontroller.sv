
import params::*;

module textcontroller(
        input sysclk,
        input [7:0] uart_val,
        input uart_recd,
        input buf_ready,
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
    
    reg [7:0] state;
    reg [7:0] cur_head;
    reg [199:0][7:0] cur_data [0:10];   
    
    reg [3:0] cur_line;
    reg [199:0][7:0] in_buffer; 
    
    reg [3:0] char_x;
    reg [3:0] char_y;
    
    reg [3:0] cur_row;
    reg [7:0] cur_col;
    
    wire [5:0][8:0] cur_char;
    wire [7:0] cur_char_ascii;
    wire [4:0] cur_width;
    wire [3:0] cur_offset;
    
    reg cyclehold;
    
    reg head_double_tmp;
    reg mid_double_tmp;
    reg [1:0][1:0] low_info_tmp;
    reg [9:0] max_scroll_tmp;
    
    reg [2:0][7:0] led_colour_tmp;
    reg [3:0] counter;
    
    reg [15:0] timeout_counter;
    
    
    assign cur_char_ascii = cur_data[cur_row][cur_col];
    assign cur_char = cur_char_ascii > 31 ? (cur_char_ascii < 123 ? FONT_LIB[cur_char_ascii - 32] : 0) : 0;
    assign cur_width = cur_char[5][4 +: 5];
    assign cur_offset = cur_char[5][0 +: 4];
        
    initial begin
        brightness = 3'b011;
        led_colour = '{8'h00, 8'h40, 8'hFF};
        state = 1;
        timeout_counter = 0;
        cur_head = 8'hFF;
        write = 0;
        switch_buf = 0;
        max_scroll = 0;
        head_double = 0;
        mid_double = 0;
        low_info = '{2'b00, 2'b00};
        cur_row = 0;
        cur_col = 0;
        for (int i = 0; i < 11; i = i + 1) begin
            cur_data[i] = '{default: 8'hFF};
        end
        
        cur_data[0][0 +: 11] = '{8'hFF, 8'h74, 8'h73, 8'h65, 8'h54, 8'h20, 8'h34, 8'h33, 8'h3A, 8'h32, 8'h31};
        cur_data[1][0 +: 8] = '{8'hFF, 8'h65, 8'h6D, 8'h69, 8'h54, 8'h20, 8'h6E, 8'h4F};
        cur_data[2][0 +: 8] = '{8'hFF, 8'h65, 8'h6D, 8'h69, 8'h54, 8'h20, 8'h6E, 8'h4F};
        cur_data[3][0 +: 57] = '{8'hFF, 8'h74, 8'h73, 8'h65, 8'h54, 8'h20, 8'h74, 8'h73, 8'h65, 8'h54, 8'h20, 8'h74, 8'h73, 8'h65, 8'h54, 8'h20, 8'h74, 8'h73, 8'h65, 8'h54, 8'h20, 8'h74, 8'h73, 8'h65, 8'h54, 8'h20, 8'h74, 8'h73, 8'h65, 8'h54, 8'h20, 8'h74, 8'h73, 8'h65, 8'h54, 8'h20, 8'h74, 8'h73, 8'h65, 8'h54, 8'h20, 8'h74, 8'h73, 8'h65, 8'h54, 8'h20, 8'h3A, 8'h74, 8'h61, 8'h20, 8'h67, 8'h6E, 8'h69, 8'h6C, 8'h6C, 8'h61, 8'h43};
        cur_data[4][0 +: 8] = '{8'hFF, 8'h65, 8'h6D, 8'h69, 8'h54, 8'h20, 8'h6E, 8'h4F};
        cur_data[5][0 +: 5] = '{8'hFF, 8'h74, 8'h73, 8'h65, 8'h54};
        cur_data[7][0 +: 5] = '{8'hFF, 8'h74, 8'h73, 8'h65, 8'h54};
    end
    
    integer i;
    
    always_ff @(posedge sysclk) begin
        uart_rst <= 0;
        write <= 0;
        case (state)
            0: begin // Listen for header
                if (uart_recd && !uart_rst) begin
                    cur_head <= uart_val;
                    uart_rst <= 1;
                    state <= 1;
                end
            end
            1: begin // Parse received header
                casez (cur_head)
                    8'h00: begin
                        for (i = 0; i < 11; i = i + 1) begin
                            cur_data[i][0] <= 8'hFF;
                        end
                        state <= 0;
                    end
                    8'hFF: begin
                        cur_col <= 0;
                        cur_row <= 0;
                        cyclehold <= 1;
                        wrt_col <= 0;
                        wrt_row <= 0;
                        out_data <= 0;
                        write <= 1;
                        head_double_tmp <= 1;
                        mid_double_tmp <= 1;
                        low_info_tmp <= '{2'b11, 2'b11};
                        max_scroll_tmp <= 0;
                        state <= 4;
                    end
                    8'hA1, 8'hA2, 8'hA3, 8'hB4, 8'hB5, 8'hC6, 8'hC7, 8'hC8, 8'hC9, 8'hCA, 8'hCB: begin
                        cur_line <= cur_head[0 +: 4] - 1;
                        state <= 2;
                    end
                    8'h1Z: begin
                        brightness <= cur_head[0 +: 3];
                        state <= 0;
                    end
                    8'h20: begin
                        state <= 5;
                        counter <= 0;
                    end
                    default: state <= 0;
                endcase
            end
            2: begin // Listen for input
                if (uart_recd && !uart_rst) begin
                    if (uart_val == 8'h00) begin
                        cur_data[cur_line] <= in_buffer;
                        state <= 0;
                    end else begin
                        in_buffer <= {in_buffer[0 +: 120], uart_val};
                    end
                    uart_rst <= 1;
                end
            end
            3: begin // Write to image buffer, then switch
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
                end else if (cur_char_ascii == 8'hFF || cur_col >= 200) begin
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
                    cyclehold <= 1;
                    cur_row <= cur_row + 1;
                    cur_col <= 0;
                    char_x <= 0;
                    char_y <= 0;
                end else if (cyclehold) begin
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
                        cyclehold <= 0;
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
            4: begin // Clear image buffer
                out_data <= 0;
                write <= 1;
                if (wrt_col == BUFFER_WIDTH - 1) begin
                    wrt_col <= 1;
                    wrt_row <= 0;
                    write <= 0;
                    state <= 3;
                end else if (wrt_row == 49) begin
                    wrt_col <= wrt_col + 1;
                    wrt_row <= 0;
                end else begin
                    wrt_row <= wrt_row + 1;
                end
            end
            5: begin
                if (counter >= 3) begin
                    if (buf_ready) begin
                        led_colour <= led_colour_tmp;
                        counter <= 0;
                        state <= 0;
                    end
                end else if (uart_recd && !uart_rst) begin
                    led_colour_tmp[counter] <= uart_val;
                    counter <= counter + 1;
                    uart_rst <= 1;
                end
            end
            default: state <= 0;
        endcase
    end 
endmodule
