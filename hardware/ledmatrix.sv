`timescale 1ns/1ps
`default_nettype none

import params::*;

module ledmatrix(
        input wire sysclk,
        input wire reset,
        input wire px0,
        input wire px1,
        input wire [2:0][7:0] px_colour,
        input wire [2:0] brightness,
        output reg [15:0] pixel_col,
        output reg [3:0] pixel_row,
        output reg [2:0] px_dat0,
        output reg [2:0] px_dat1,
        output reg scroll,
        output logic [3:0] address,
        output logic outenable,
        output logic latch
    );

    localparam BCM_CYCLES_SHIFT = $clog2(BCM_CYCLES);
    
    // Data to output
    reg [15:0] counter; // 0-65535
    reg [15:0] cur_wait; // cycles to wait in current BCM cycle
    reg [3:0] line; // 0-15
    reg [3:0] cur_bit; // Bit number for BCM
    
    reg [15:0] scroll_delay;
    
    reg [2:0] pwm;
    reg blank;
    
    wire [2:0][7:0] colour0;
    wire [2:0][7:0] colour1;

    assign colour0[0] = px0 ? px_colour[0] : 8'h0;
    assign colour0[1] = px0 ? px_colour[1] : 8'h0;
    assign colour0[2] = px0 ? px_colour[2] : 8'h0;

    assign colour1[0] = px1 ? px_colour[0] : 8'h0;
    assign colour1[1] = px1 ? px_colour[1] : 8'h0;
    assign colour1[2] = px1 ? px_colour[2] : 8'h0;
    
    assign outenable = blank || (pwm > brightness);
    
    //assign latch = (counter == WIDTH - 2); // Allow 1 extra cycle to avoid off-by-one on pixel data
    assign address = line;

    logic bcm_flag;
    logic final_bcm;
    logic low_line;
    logic scroll_cond;

    assign bcm_flag = counter >= (cur_wait << BCM_CYCLES_SHIFT) + 1;
    assign final_bcm = cur_bit == COL_DEPTH - 1;
    assign low_line = line == 4'hf;
    assign scroll_cond = scroll_delay == SCROLL_SPEED - 1;
    
    always_ff @(posedge sysclk) begin
        // control logic
        if (reset) begin
            pwm          <= 0;
            scroll       <= 0;
            scroll_delay <= 0;
            counter      <= 0;
            cur_wait     <= 0;
            cur_bit      <= 0;
            line         <= 0;

            pixel_col <= 0;
            pixel_row <= 0;
        end else begin
            pwm <= pwm + 1;

            scroll <= bcm_flag && final_bcm && low_line && scroll_cond;
            if (bcm_flag && final_bcm && low_line) begin
                scroll_delay <= scroll_cond ? 0 : scroll_delay + 1;
            end

            counter <= bcm_flag ? 0 : counter + 1;

            // bcm controls
            if (bcm_flag) begin
                cur_wait <= final_bcm ? 1 : cur_wait << 1;
                cur_bit  <= final_bcm ? 0 : cur_bit + 1;
            end

            line <= bcm_flag && final_bcm ? line + 1 : line;

            // Set address for next read
            pixel_col <= (counter >= WIDTH) ? 0 : counter + 1;
            pixel_row <= (counter >= WIDTH && final_bcm) ? line + 1 : line;
        end

        latch <= (counter == WIDTH - 3);

        // disable for new bit of BCM
        // disable for first line of BCM
        blank <= bcm_flag || ((counter < WIDTH + 2) && (cur_bit == 0));

        px_dat0[0] <= colour0[0][cur_bit + (8 - COL_DEPTH)];
        px_dat0[1] <= colour0[1][cur_bit + (8 - COL_DEPTH)];
        px_dat0[2] <= colour0[2][cur_bit + (8 - COL_DEPTH)];
        px_dat1[0] <= colour1[0][cur_bit + (8 - COL_DEPTH)];
        px_dat1[1] <= colour1[1][cur_bit + (8 - COL_DEPTH)];
        px_dat1[2] <= colour1[2][cur_bit + (8 - COL_DEPTH)];
    end

    `ifdef FORMAL
        logic f_past_valid;
        initial f_past_valid = 1'b0;
        always @(posedge sysclk) f_past_valid <= 1'b1;

        initial assume(reset);

        always_ff @(posedge sysclk) begin
            if (f_past_valid && !$past(reset)) begin
                cur_bit_bounded: assert(cur_bit < COL_DEPTH);

                pixel_col_bounded: assert(pixel_col <= WIDTH);

                bcm_length_doubles: assert(cur_wait == 16'd1 << cur_bit);

                address_change_by_one: assert(
                    address == $past(address) ||
                    address == $past(address) + 1 ||
                    (address == 0 && $past(address) = 15)
                    );

                scroll_pulse: assert(!(scroll && $past(scroll)));

                latch_pulse: assert(!(latch && $past(latch)));
            end
        end

        // cover properties
        always_ff @(posedge sysclk) begin
            cover (f_past_valid && bcm_flag && final_bcm);
            cover (f_past_valid && low_line);
            cover (f_past_valid && scroll);
        end
    `endif
endmodule
