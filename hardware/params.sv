
package params;

    localparam CLK_FREQ = 12_000_000;
    localparam BAUD_RATE = 38_400;
    
    localparam integer CYCLES_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam integer SAMPLE_POINT = CYCLES_PER_BIT / 2;
    
    localparam WIDTH = 196;
    localparam HEIGHT = 32;
    localparam NUM_PIXELS = WIDTH * HEIGHT;

    localparam BCM_CYCLES = 256; // Number of cycles to wait in BCM
    // n bit colour -> 16 * ( 2^n - 1) * WAIT_CYCLES
    
    localparam COL_DEPTH = 4;
    
    localparam GAMMA_VAL = 2.1;
    
    localparam SCROLL_SPEED = 4; // Frames per pixel of scrolling
    localparam BUFFER_WIDTH = 1024; // Max pixel width
    localparam BUFFER_WIDTH_LOG = $clog2(BUFFER_WIDTH);
    
    localparam TITLE_CYCLES = 200;
    localparam MESSAGE_CYCLES = 400;
    localparam DEST_CYCLES = 400;

endpackage
