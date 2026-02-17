`timescale 1ns / 1ps

import params::*;

module top(
        input sysclk,
        input uart_txd_in,
        output rp0,
        output gp0,
        output bp0,
        output rp1,
        output gp1,
        output bp1,
        output adra,
        output adrb,
        output adrc,
        output adrd,
        output adre,
        output outclock,
        output reg outenable,
        output reg latch
    );
    
    wire [2:0][7:0] led_colour; //'{8'h00, 8'h40, 8'hFF}
    wire [2:0] brightness; // 3'b011
    wire [2:0][7:0] proc_colour;
    
    wire [3:0] addr;
    wire out_up;
    wire out_lo;
    wire [15:0] pixel_col;
    wire [3:0] pixel_row;
    wire [2:0] px_dat0;
    wire [2:0] px_dat1;
    wire scroll;
    
    wire [7:0] uart_val;
    wire uart_recd;
    wire uart_rst;
    
    wire buf_ready;
    
    wire [15:0] wrt_col;
    wire [5:0] wrt_row;
    wire wrt_data;
    wire write;
    wire [9:0] max_scroll;
    wire switch_buf;
    wire head_double;
    wire mid_double;
    wire [1:0][1:0] low_info;
    
    
    assign {adrd, adrc, adrb, adra} = addr;
    assign adre = 1'b0;
    
    assign rp0 = px_dat0[0];
    assign gp0 = px_dat0[1];
    assign bp0 = px_dat0[2];
    assign rp1 = px_dat1[0];
    assign gp1 = px_dat1[1];
    assign bp1 = px_dat1[2];
    
    assign outclock = sysclk;
    
    uart_rx rx0(
        .clk(sysclk),
        .read(uart_rst),
        .rx_in(uart_txd_in),
        .value(uart_val),
        .par_ok(),
        .recd(uart_recd)
    );
    
    imgprocess proc0(
        .in(led_colour),
        .out(proc_colour)
    );
    
    ledmatrix driv0(
        .sysclk(sysclk),
        .px0(out_up),
        .px1(out_lo),
        .px_colour(proc_colour),
        .brightness(brightness),
        .pixel_col(pixel_col),
        .pixel_row(pixel_row),
        .px_dat0(px_dat0),
        .px_dat1(px_dat1),
        .scroll(scroll),
        .address(addr),
        .outenable(outenable),
        .latch(latch)
    );
    
    imgbuffer buf0(
        .sysclk(sysclk),
        .buf_select(switch_buf),
        .write(write),
        .in_data(wrt_data),
        .in_col(wrt_col),
        .in_row(wrt_row),
        .out_col(pixel_col),
        .out_row(pixel_row),
        .scroll(scroll),
        .max_scroll(max_scroll),
        .head_double(head_double),
        .mid_double(mid_double),
        .low_info(low_info),
        .out_up(out_up),
        .out_lo(out_lo),
        .buf_ready(buf_ready)
    );
    
    textcontroller ctrl0(
        .sysclk(sysclk),
        .uart_val(uart_val),
        .uart_recd(uart_recd),
        .buf_ready(buf_ready),
        .uart_rst(uart_rst),
        .wrt_col(wrt_col),
        .wrt_row(wrt_row),
        .out_data(wrt_data),
        .write(write),
        .max_scroll(max_scroll),
        .switch_buf(switch_buf),
        .head_double(head_double),
        .mid_double(mid_double),
        .low_info(low_info),
        .brightness(brightness),
        .led_colour(led_colour)
    );
endmodule
