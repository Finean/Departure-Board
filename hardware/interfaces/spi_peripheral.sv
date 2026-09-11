`timescale 1ns/1ps
`default_nettype none


// Ensure clk is around 10x faster than sclk
module spi_peripheral #(
    parameter [7:0] POCI_DEFAULT = 8'h0,
        parameter [1:0] SPI_MODE = 0,
    parameter bit CPOL = SPI_MODE[1], // sclk idle polarity
    parameter bit CPHA = SPI_MODE[0] // sclk phase
    )(
    // io on sclk domain
    input wire i_spi_clk,
    input wire i_pico,
    input wire i_cs, // active low
    output logic o_poci,

    // io on fpga clock domain
    input wire clk,
    input wire reset,
    // dout
    output logic [7:0] o_dout,
    output logic o_dout_valid,
    input wire i_dout_ready,
    // din
    input wire [7:0] i_din,
    input wire i_din_valid,
    output logic o_din_ready,

    output logic [2:0] f_sample_bit
    );

    // uses 8 bit packets, MSB first

    (* ASYNC_REG = "TRUE" *) logic [2:0] sclk_sync;
    (* ASYNC_REG = "TRUE" *) logic [2:0] pico_sync;
    (* ASYNC_REG = "TRUE" *) logic [2:0] cs_sync;
    logic sclk_posedge, sclk_negedge;
    logic cs_posedge, cs_negedge;

    always_ff @(posedge clk) begin
        sclk_sync <= {sclk_sync[1:0], i_spi_clk};
        pico_sync <= {pico_sync[1:0], i_pico};
        cs_sync <= {cs_sync[1:0], i_cs};
    end

    generate
        if (CPHA) begin: SAMPLE_NEGEDGE
            always_ff @(posedge clk) begin
                sclk_posedge <= sclk_sync[2:1] == 2'b10;
                sclk_negedge <= sclk_sync[2:1] == 2'b01;
            end
        end else begin: SAMPLE_POSEDGE
            always_ff @(posedge clk) begin
                sclk_posedge <= sclk_sync[2:1] == 2'b01;
                sclk_negedge <= sclk_sync[2:1] == 2'b10;
            end
        end
    endgenerate

    logic active;
    assign active = !cs_sync[1];

    logic [7:0] spi_din_sreg;
    logic [7:0] spi_din_latched;
    logic [2:0] spi_din_counter;
    logic spi_din_new;

    assign f_sample_bit = spi_din_counter;

    // Read side from PICO pin
    always_ff @(posedge clk) begin
        cs_posedge <= cs_sync[2:1] == 2'b01;
        cs_negedge <= cs_sync[2:1] == 2'b10;

        if (o_dout_valid && i_dout_ready) begin
            o_dout_valid <= 1'b0;
        end

        spi_din_new <= 1'b0;
        o_dout <= o_dout;
        if (reset) begin
            spi_din_counter <= 3'b0;
            spi_din_latched <= 0;
            o_dout_valid <= 1'b0;
        end else begin
            if (!active) begin
                spi_din_counter <= 0;
            end

            if (sclk_posedge && active) begin
                spi_din_counter <= spi_din_counter + 1;
                spi_din_new <= spi_din_counter == 3'b111;
            end

            // Transmit new byte
            if (spi_din_new) begin
                o_dout <= spi_din_latched;
                o_dout_valid <= 1'b1;
            end
        end

        // Shift + detect end of byte and latch
        if (sclk_posedge && active) begin
            spi_din_sreg <= {spi_din_sreg[0+:7], pico_sync[2]};
            spi_din_latched <= (spi_din_counter == 3'b111) ? {spi_din_sreg[0+:7], pico_sync[2]} : spi_din_latched;
        end
    end

    logic [7:0] spi_dout_latched;
    logic [2:0] spi_dout_counter;

    logic [7:0] spi_dout_reg;
    logic spi_dout_ready;

    logic poci;
    logic latch_next;
    logic latch_block;

    assign o_poci = active ? poci : 1'bZ;
    assign latch_next = spi_dout_counter == 3'b0;

    // Write side
    always_ff @(posedge clk) begin
        o_din_ready <= !spi_dout_ready;
        
        if (reset) begin
            latch_block <= 1'b0;
            spi_dout_latched <= POCI_DEFAULT;
            spi_dout_reg <= 8'h0;
            spi_dout_counter <= 3'b0;
            spi_dout_ready <= 1'b0;
        end else begin
            if (!active) begin
                spi_dout_counter <= 1;
                poci <= spi_dout_latched[7];
            end

            if (sclk_negedge && active) begin
                spi_dout_counter <= spi_dout_counter + 1;
                // MSB first
                poci <= spi_dout_latched[7 - spi_dout_counter];
                latch_block <= 1'b0;
            end

            if (i_din_valid && o_din_ready) begin
                spi_dout_reg <= i_din;
                spi_dout_ready <= 1'b1;
                o_din_ready <= 1'b0;
            end

            if (spi_dout_ready && latch_next) begin
                spi_dout_ready <= 1'b0;
                o_din_ready <= 1'b1;
                spi_dout_latched <= spi_dout_reg;
                latch_block <= 1'b1;
            end else if (!latch_block && latch_next) begin
                spi_dout_latched <= POCI_DEFAULT;
                latch_block <= 1'b1;
            end
        end
    end
endmodule
