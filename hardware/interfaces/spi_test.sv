`timescale 1ns/1ps
`default_nettype none


module spi_test (
        input wire sysclk,
        input wire rst_btn, // active high
        input wire sclk,
        input wire cs,
        input wire pico,
        output wire poci,
        output logic led0_r,
        output logic led0_g,
        output logic led0_b
    );

    logic initial_reset;

    logic reset;
    assign reset = rst_btn || initial_reset;

    logic [3:0] pwm;

    logic pico_valid, pico_ready;
    logic poci_valid, poci_ready;
    logic [7:0] pico_data;
    logic [7:0] poci_data;

    always @(posedge sysclk) begin
        initial_reset <= 1'b0;

        if (reset) begin
            pwm <= 4'b0;
        end else begin
            pwm <= pwm + 1;
        end

        led0_r <= !(!cs && pwm[3] && pwm[2]);
        led0_g <= 1'b1;
        led0_b <= 1'b1;
    end   

    wire [2:0] f_sample_bit; 

    spi_peripheral #(
        .SPI_MODE     (0)
     ) spi_peripheral (
        .i_spi_clk   (sclk),
        .i_pico      (pico),
        .i_cs        (cs),
        .o_poci      (poci),
        .clk         (sysclk),
        .reset       (reset),
        .o_dout      (pico_data),
        .o_dout_valid(pico_valid),
        .i_dout_ready(pico_ready),
        .i_din       (poci_data),
        .i_din_valid (poci_valid),
        .o_din_ready (poci_ready),
        .f_sample_bit(f_sample_bit)
    );

    `ifdef SYNTHESIS
        initial begin
            initial_reset = 1'b1;
            pwm = 4'b0;
        end
    `endif

    `ifdef FORMAL
        (* gclk *) logic f_clk;

        logic f_past_valid;
        initial f_past_valid = 1'b0;
        always @(posedge sysclk) f_past_valid <= 1'b1;

        initial assume(rst_btn);

        logic [7:0] f_sysclk_ctr;
        logic [7:0] f_sclk_ctr;

        initial begin
            f_sysclk_ctr = 0;
            f_sclk_ctr = 0;
        end

        // Set clock behevaiour
        always @(*) begin
            assume(sysclk == f_sysclk_ctr[0]);
            // 8 times slower
            assume(sclk == f_sclk_ctr[3] && !cs);
        end

        logic [7:0] f_byte_a, f_byte_b;
        logic [7:0] f_pico_byte, f_poci_byte;
        logic [7:0] f_poci_recd, f_poci_active;
        logic [2:0] f_pico_ctr, f_poci_ctr;
        logic f_pico_xa, f_poci_xa, f_poci_listen;

        logic sample, shift, active;

        logic f_psclk;

        assign sample = sclk && !f_psclk;
        assign shift  = !sclk && f_psclk;
        assign active = !cs;

        initial begin
            f_pico_xa = 0;
            f_poci_xa = 0;
            poci_valid = 0;
            f_poci_listen = 0;
        end 

        always @(posedge f_clk) begin
            f_psclk <= sclk;
            f_byte_a <= $anyconst;
            f_byte_b <= $anyconst;

            if (pico ^ $past(pico)) begin
                data_shifted_on_shift: assume(shift || $past(shift));
            end

            if (poci_ready && poci_valid) begin
                poci_valid <= 1'b0;
            end

            if (f_past_valid && (sample || $past(sample))) begin
                sample_cntr_increments: assert(f_sample_bit == $past(f_sample_bit) + 3'b1);
            end

            if (f_past_valid && $past(sysclk) && ($past(cs) || $past(rst_btn))) begin
                sample_cntr_resets_sync: assert(f_sample_bit == 0);
            end

            if (active && f_past_valid && !$past(reset)) begin
                // Test shifting in values, check they match the output value on pico_data
                if (shift && f_sample_bit == 3'b0) begin
                    f_pico_xa <= 1'b1;
                    f_pico_byte <= f_byte_a;
                end

                if ($past(shift) && f_pico_xa) begin
                    assume(pico == f_pico_byte[7 - f_sample_bit]);
                end

                if (pico_valid && !$past(pico_valid)) begin
                    correct_pico: assert(pico_data == $past(f_pico_byte));
                    pico_xa: assert(f_pico_xa);
                end


                // Test writing value into poci_data
                if (f_sample_bit == 3'b101 && poci_ready) begin
                    f_poci_xa <= 1'b1;
                    f_poci_byte <= f_byte_b;
                    f_poci_listen <= 1'b0;
                end

                if (f_poci_xa && poci_ready) begin
                    poci_data <= f_poci_byte;
                    poci_valid <= 1'b1;
                end

                if (f_sample_bit == 3'b0 && f_poci_xa && !f_poci_listen) begin
                    f_poci_listen <= 1'b1;
                    f_poci_active <= $past(f_poci_byte);
                end

                if (f_poci_listen) begin
                    assert(f_poci_xa);

                    if (sample) begin
                        f_poci_recd <= {f_poci_recd[0+:7], poci};
                    end

                    if (f_sample_bit == 3'b0) begin
                        f_poci_listen <= 1'b0;
                        correct_poci: assert(f_poci_recd == $past(f_poci_active));
                    end
                end
                
            end else begin
                f_pico_xa <= 1'b0;
                f_poci_xa <= 1'b0;
                f_poci_listen <= 1'b0;
            end
        end
    `else
        // Join RX and TX together to test
        assign poci_data = pico_data;
        assign pico_ready = poci_ready;
        assign poci_valid = pico_valid;
    `endif
endmodule
