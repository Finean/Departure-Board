`timescale 1ns/1ps
`default_nettype none

import params::*;

module imgprocess(
        input wire [2:0][7:0] in,
        output logic [2:0][7:0] out
    );
    
    function int gamma_fn (input int x);
        real xf, yf;
        xf = x / 255.0;
        yf = xf ** GAMMA_VAL;   // gamma = 2.2
        return int'(yf * 255.0);
    endfunction
    
    function automatic void init_gamma_lut(ref logic [7:0] lut[0:255]);
        for (int i = 0; i < 256; i = i + 1) begin
            lut[i] = gamma_fn(i);
        end
    endfunction
    
    logic [7:0] GAMMA_LUT[0:255];
    
    initial begin
        init_gamma_lut(GAMMA_LUT);
    end
    
    integer k;
    
    always @(*) begin
        for (k = 0; k < 3; k = k + 1) begin
            out[k] = GAMMA_LUT[in[k]];
        end
    end
endmodule