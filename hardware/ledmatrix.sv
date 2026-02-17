
import params::*;

module ledmatrix(
        input sysclk,
        input px0,
        input px1,
        input [2:0][7:0] px_colour,
        input [2:0] brightness,
        output reg [15:0] pixel_col,
        output reg [3:0] pixel_row,
        output reg [2:0] px_dat0,
        output reg [2:0] px_dat1,
        output reg scroll,
        output [3:0] address,
        output outenable,
        output latch
    );
    
    // Data to output
    reg [15:0] counter; // 0-65535
    reg [15:0] cur_wait;
    reg [3:0] line; // 0-15
    reg [3:0] cur_bit; // Bit number for BCM
    
    reg [15:0] scroll_delay;
    
    reg [2:0] pwm;
    reg blank;
    
    wire [2:0][7:0] colour0 = px0 ? px_colour : '{8'h00, 8'h00, 8'h00};
    wire [2:0][7:0] colour1 = px1 ? px_colour : '{8'h00, 8'h00, 8'h00};
    
    assign outenable = blank || (pwm > brightness);
    
    assign latch = (counter == WIDTH - 2) && sysclk; // Allow 1 extra cycle to avoid off-by-one on pixel data
    assign address = line;
    
    initial begin
        pwm = 0;
        counter = 0;
        scroll = 0;
        scroll_delay = 0;
        cur_bit = 0;
        line = 0;
        cur_wait = 1;
        px_dat0 = 0;
        px_dat1 = 0;
        blank = 1;
        pixel_col = 0;
        pixel_row = 0;
    end
    
    always_ff @(posedge sysclk) begin
    
        counter <= counter + 1;
        pwm <= pwm + 1;
        scroll <= 0;
        
        // Binary coded modulation
        if (counter >= (cur_wait * BCM_CYCLES + 1)) begin
            blank <= 1;
            if (cur_bit == (COL_DEPTH - 1)) begin // Next line
                cur_wait <= 1;
                counter <= 0;
                cur_bit <= 0;
                line <= line + 1;
                if (line == 4'hF) begin
                    if (scroll_delay == SCROLL_SPEED - 1) begin
                        scroll_delay <= 0;
                        scroll <= 1;
                    end else begin
                        scroll_delay <= scroll_delay + 1;
                    end
                end
            end else begin // Next bit
                counter <= 0;
                cur_wait <= (cur_wait << 1);
                cur_bit <= cur_bit + 1;
            end
        end else if (counter < (WIDTH + 2) && (cur_bit == 0)) begin // Disable for first line
            blank <= 1;
        end else
            blank <= 0;
            
        px_dat0[0] <= colour0[0][cur_bit + (8 - COL_DEPTH)];
        px_dat0[1] <= colour0[1][cur_bit + (8 - COL_DEPTH)];
        px_dat0[2] <= colour0[2][cur_bit + (8 - COL_DEPTH)];
        px_dat1[0] <= colour1[0][cur_bit + (8 - COL_DEPTH)];
        px_dat1[1] <= colour1[1][cur_bit + (8 - COL_DEPTH)];
        px_dat1[2] <= colour1[2][cur_bit + (8 - COL_DEPTH)];
        
        // Set address for next read
        if (counter >= WIDTH) begin
            pixel_col <= 0;
            if (cur_bit == (COL_DEPTH - 1)) begin
                pixel_row <= line + 1;
            end else begin
                pixel_row <= line;
            end
        end else begin
            pixel_col <= counter + 1;
            pixel_row <= line;
        end
    end
endmodule
