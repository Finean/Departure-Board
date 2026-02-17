
import params::*;

module imgbuffer(
        input sysclk,
        input buf_select,
        input write,
        input in_data,
        input [15:0] in_col,
        input [5:0] in_row,
        input [15:0] out_col,
        input [3:0] out_row,
        input scroll,
        input [9:0] max_scroll,
        input head_double,
        input mid_double,
        input [1:0][1:0] low_info,
        output logic out_up,
        output logic out_lo,
        output reg buf_ready
    );
    
    (* ram_style = "block" *) reg front_buf [0:49 * BUFFER_WIDTH - 1];
    (* ram_style = "block" *) reg rear_buf [0:49 * BUFFER_WIDTH - 1];
    
    // 0-8 HEAD, 9-10 br, 11-19 MID, 19-20 br, 21 - 30 LOW, 31 br
    // 0-8 HEAD, 9-10 br, 11-28 MID, 29-30 br, 31 - 48 LOW
    // WIDTH - 46 for etd
    
    
    reg head_state;
    reg mid_state;
    reg [1:0] low_state;
    reg [15:0] buf_scroll;
    reg [15:0] title_counter;
    reg [15:0] mid_counter;
    reg [15:0] dest_counter;
    
    logic [15:0] calc_col_hi;
    logic [5:0] calc_row_hi;
    logic [15:0] calc_col_lo;
    logic [5:0] calc_row_lo;
    
    logic [15:0] wrt_addr;
    logic [15:0] raddr_hi;
    logic [15:0] raddr_lo;
    logic [15:0] faddr_hi;
    logic [15:0] faddr_lo;
    
    wire [15:0] temp_addr_hi;
    wire [15:0] temp_addr_lo;
    wire [15:0] temp_addr_wrt;
    
    reg write_sync;
    reg val_sync;
    
    integer i;
    
    initial begin
        for (i = 0; i < 49 * BUFFER_WIDTH; i = i + 1) begin
            front_buf[i] = 0;
            rear_buf[i] = 0;
        end
        title_counter = 0;
        mid_counter = 0;
        dest_counter = 0;
        head_state = 0;
        mid_state = 0;
        low_state = 2'b00;
        out_up = 0;
        out_lo = 0;
        buf_scroll = 0;
        write_sync = 0;
    end
    
    always_comb begin
        // out_row =  11 - 20 should be scrolled by scroll
        // Upper pixel
        if (out_row < 11) begin
            if (!head_state || !head_double) begin
                calc_row_hi = out_row;
                calc_col_hi = out_col;
            end else begin
                calc_row_hi = out_row;
                if (out_col < WIDTH - 43) begin
                    calc_col_hi = out_col + WIDTH;
                end else begin
                    calc_col_hi = out_col;
                end
            end
        end else if (!mid_state || !mid_double) begin
            calc_row_hi = out_row;
            if (buf_scroll > 64) begin
                    calc_col_hi = out_col + buf_scroll - 64;
                end else begin
                    calc_col_hi = out_col;
                end
        end else begin
            calc_row_hi = out_row + 9;
            calc_col_hi = out_col;
        end
    
        // Lower pixel
        if (out_row == 4 || out_row == 5 || out_row == 15) begin
            calc_row_lo = 30;
            calc_col_lo = out_col;
        end else if (out_row < 4) begin
            if (!mid_state || !mid_double) begin
                calc_row_lo = out_row + 16;
                if (buf_scroll > 64) begin
                    calc_col_lo = out_col + buf_scroll - 64;
                end else begin
                    calc_col_lo = out_col;
                end
            end else begin
                calc_row_lo = out_row + 25;
                calc_col_lo = out_col;
            end
        end else begin
            if (!low_state[1]) begin
                if (!low_state[0] || !low_info[0][1]) begin
                    calc_row_lo = out_row + 25;
                    calc_col_lo = out_col;
                end else begin
                    calc_row_lo = out_row + 25;
                    if (out_col <  WIDTH - 43) begin
                        calc_col_lo = out_col + WIDTH;
                    end else begin
                        calc_col_lo = out_col;
                    end
                end
            end else begin
                if (!low_state[0] || !low_info[1][1]) begin
                    calc_row_lo = out_row + 34;
                    calc_col_lo = out_col;
                end else begin
                    calc_row_lo = out_row + 34;
                    if (out_col < WIDTH - 43) begin
                        calc_col_lo = out_col + WIDTH;
                    end else begin
                        calc_col_lo = out_col;
                    end
                end
            end
        end
    end
    
    assign temp_addr_hi = (calc_row_hi * BUFFER_WIDTH) + calc_col_hi;
    assign temp_addr_lo = (calc_row_lo * BUFFER_WIDTH) + calc_col_lo;
    assign temp_addr_wrt = (in_row * BUFFER_WIDTH) + in_col;
    
    always_ff @(posedge sysclk) begin
        if (out_col == WIDTH && out_row == 15) begin
            buf_ready <= 1;
        end else begin
            buf_ready <= 0;
        end
        
        raddr_hi <= buf_select ? temp_addr_hi : temp_addr_wrt;
        raddr_lo <= temp_addr_lo;
        faddr_hi <= buf_select ? temp_addr_wrt : temp_addr_hi;
        faddr_lo <= temp_addr_lo;
        write_sync <= write;
        val_sync <= in_data;
        
    
        // Scroll control
        if (scroll) begin
            title_counter <= title_counter + 1;
            dest_counter <= dest_counter + 1;
            mid_counter <= mid_counter + 1;
            
            if (buf_scroll > BUFFER_WIDTH) begin
                buf_scroll <= 0;
            end
            
            if ((max_scroll > 0 && buf_scroll >= max_scroll) || (max_scroll == 0 && mid_counter >= MESSAGE_CYCLES)) begin
                if (mid_double) begin
                    mid_state <= 1;
                    mid_counter <= 0;
                end
                buf_scroll <= 0;
            end else begin
                if (mid_state == 0 && max_scroll > 0) begin
                    buf_scroll <= buf_scroll + 1;
                end
            end 
            
            if (mid_counter == MESSAGE_CYCLES && mid_state == 1) begin
                buf_scroll <= 0;
                mid_state <= 0;
            end
            
            if (title_counter == TITLE_CYCLES) begin
                if (head_double) begin
                    head_state <= ~head_state;
                end
                if (low_info[low_state[1]][0]) begin
                    low_state[0] <= ~low_state[0];
                end
                title_counter <= 0;
            end
            
            if (dest_counter == DEST_CYCLES) begin
                if (low_info[1][0]) begin
                    low_state[1] <= ~low_state[1];
                    low_state[0] <= 0;
                    title_counter <= 0;
                end
                dest_counter <= 0;
            end
        end
    
        // Read/Write logic
        if (buf_select) begin
            // Write logic
            if (write_sync) begin
                front_buf[faddr_hi] <= val_sync;
            end
            
            out_up <= rear_buf[raddr_hi];
            out_lo <= rear_buf[raddr_lo];
            
        end else begin // Second buffer
            // Write logic
            if (write_sync) begin
                rear_buf[raddr_hi] <= val_sync;
            end
            
            out_up <= front_buf[faddr_hi];
            out_lo <= front_buf[faddr_lo];
        end
    end 
endmodule
