/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Scrolling text renderer for "SILICONIMIST".
 *
 * Renders a horizontally-scrolling marquee using a compact 5×7 pixel font,
 * 2× scaled to 10×14 on screen.  Each character cell is 16 screen pixels
 * wide (8 font-pixel slots × 2-pixel scale; 5 glyph columns + 3 gap), so
 * the 12-character string plus 4 blank spacer slots fit in a 256-pixel
 * tiling period that wraps seamlessly across the 640-pixel display.
 *
 * With the scroll offset advancing once per frame (~60 Hz) the text moves
 * at 60 px/s — roughly 4 seconds per full 256-px cycle.  About 2.5 copies
 * of "SILICONIMIST" are visible at once, giving a continuous marquee effect.
 *
 * Font storage: 9 glyphs (S I L C O N M T + blank) × 8 row slots × 5 bits
 * = 360 bits (a ~46× saving over the 16 384-bit monolithic bitmap ROM).
 * The glyph ROM is addressed by {glyph_index[3:0], row[2:0]}, making the
 * hardware a simple 7-bit LUT lookup.
 *
 * Inputs:
 *   pix_x, pix_y  – current pixel coordinates from hvsync_generator
 *   scroll        – horizontal scroll offset; 8 LSBs position within the
 *                   256-px tiling period (advance by 1 each frame)
 *
 * Outputs:
 *   pixel  – high when this pixel is a lit glyph foreground pixel
 *   active – high when (pix_x, pix_y) is inside the text band
 *
 * Font encoding: LSB-first (bit 0 = leftmost column 0, bit 4 = rightmost
 * column 4), so the pixel at column C is simply glyph_row[C].
 */

`default_nettype none

module text_scroller (
    input  wire [9:0] pix_x,
    input  wire [9:0] pix_y,
    input  wire [9:0] scroll,
    output wire       pixel,
    output wire       active
);

  // Text band: 14 screen-pixels tall (7 font rows × 2-pixel scale).
  // Placed near the bottom of the 480-line display.
  localparam [9:0] TEXT_Y     = 10'd456;
  localparam [9:0] TEXT_Y_END = 10'd470;  // TEXT_Y + 14

  wire in_y_band = (pix_y >= TEXT_Y) && (pix_y < TEXT_Y_END);

  // -------------------------------------------------------------------
  // Horizontal addressing within the 256-pixel tiling period
  // -------------------------------------------------------------------
  // 8-bit wrap gives the 256-px period naturally.
  wire [7:0] sx = pix_x[7:0] + scroll[7:0];

  // Character cell index within the 16-cell (256-px) period.
  wire [3:0] char_idx = sx[7:4];   // 0..15

  // Column within the cell (0..7); columns 5..7 are gap (blank).
  wire [2:0] char_col = sx[3:1];

  // -------------------------------------------------------------------
  // Vertical addressing within the 14-pixel band
  // -------------------------------------------------------------------
  // TEXT_Y[3:0] == 4'd8, so a 4-bit subtraction wraps correctly for
  // all pix_y in [456, 469].  Result range: 0..13 (14 rows).
  wire [3:0] row_in_band = pix_y[3:0] - TEXT_Y[3:0];
  wire [2:0] char_row    = row_in_band[3:1];  // ÷2 for 2× scale → 0..6

  // -------------------------------------------------------------------
  // Sequence ROM: char slot → glyph index
  // -------------------------------------------------------------------
  // "SILICONIMIST" occupies slots 0..11; slots 12..15 are blank.
  // Glyph indices: S=0 I=1 L=2 C=3 O=4 N=5 M=6 T=7  blank=8
  reg [3:0] char_seq [0:15];
  initial begin
    char_seq[ 0] = 4'd0;  // S
    char_seq[ 1] = 4'd1;  // I
    char_seq[ 2] = 4'd2;  // L
    char_seq[ 3] = 4'd1;  // I
    char_seq[ 4] = 4'd3;  // C
    char_seq[ 5] = 4'd4;  // O
    char_seq[ 6] = 4'd5;  // N
    char_seq[ 7] = 4'd1;  // I
    char_seq[ 8] = 4'd6;  // M
    char_seq[ 9] = 4'd1;  // I
    char_seq[10] = 4'd0;  // S
    char_seq[11] = 4'd7;  // T
    char_seq[12] = 4'd8;  // blank
    char_seq[13] = 4'd8;  // blank
    char_seq[14] = 4'd8;  // blank
    char_seq[15] = 4'd8;  // blank
  end

  wire [3:0] cur_glyph = char_seq[char_idx];

  // -------------------------------------------------------------------
  // Font ROM: 9 glyphs × 8 row slots, 5 bits per row (LSB-first)
  // -------------------------------------------------------------------
  // Address: {glyph[3:0], row[2:0]} — 7 bits → 128 entries.
  // Only 9×7 = 63 entries are meaningful; the rest default to 0.
  //
  // LSB-first means bit N is lit when char_col == N, so the pixel
  // select is simply: glyph_row_data[char_col].
  //
  // Glyph bitmaps (each row shown left-to-right, X = lit, . = dark):
  //
  //  S       I       L       C       O       N       M       T
  //  .XXX.   XXXXX   X....   .XXX.   .XXX.   X...X   X...X   XXXXX
  //  X...X   ..X..   X....   X...X   X...X   XX..X   XX.XX   ..X..
  //  X....   ..X..   X....   X....   X...X   X.X.X   X.X.X   ..X..
  //  .XXX.   ..X..   X....   X....   X...X   X..XX   X...X   ..X..
  //  ....X   ..X..   X....   X....   X...X   X...X   X...X   ..X..
  //  X...X   ..X..   X....   X...X   X...X   X...X   X...X   ..X..
  //  .XXX.   XXXXX   XXXXX   .XXX.   .XXX.   X...X   X...X   ..X..

  reg [4:0] font [0:127];
  integer fi;
  initial begin
    // Unwritten entries must be driven (otherwise font[] reads as X under Icarus
    // simulation and XOR-masks through the marquee, breaking framebuffer tests).
    for (fi = 0; fi < 128; fi = fi + 1)
      font[fi] = 5'b00000;
    // --- Glyph 0: S ---
    font[{4'd0, 3'd0}] = 5'b01110;  // .XXX.
    font[{4'd0, 3'd1}] = 5'b10001;  // X...X
    font[{4'd0, 3'd2}] = 5'b00001;  // X....
    font[{4'd0, 3'd3}] = 5'b01110;  // .XXX.
    font[{4'd0, 3'd4}] = 5'b10000;  // ....X
    font[{4'd0, 3'd5}] = 5'b10001;  // X...X
    font[{4'd0, 3'd6}] = 5'b01110;  // .XXX.

    // --- Glyph 1: I ---
    font[{4'd1, 3'd0}] = 5'b11111;  // XXXXX
    font[{4'd1, 3'd1}] = 5'b00100;  // ..X..
    font[{4'd1, 3'd2}] = 5'b00100;  // ..X..
    font[{4'd1, 3'd3}] = 5'b00100;  // ..X..
    font[{4'd1, 3'd4}] = 5'b00100;  // ..X..
    font[{4'd1, 3'd5}] = 5'b00100;  // ..X..
    font[{4'd1, 3'd6}] = 5'b11111;  // XXXXX

    // --- Glyph 2: L ---
    font[{4'd2, 3'd0}] = 5'b00001;  // X....
    font[{4'd2, 3'd1}] = 5'b00001;  // X....
    font[{4'd2, 3'd2}] = 5'b00001;  // X....
    font[{4'd2, 3'd3}] = 5'b00001;  // X....
    font[{4'd2, 3'd4}] = 5'b00001;  // X....
    font[{4'd2, 3'd5}] = 5'b00001;  // X....
    font[{4'd2, 3'd6}] = 5'b11111;  // XXXXX

    // --- Glyph 3: C ---
    font[{4'd3, 3'd0}] = 5'b01110;  // .XXX.
    font[{4'd3, 3'd1}] = 5'b10001;  // X...X
    font[{4'd3, 3'd2}] = 5'b00001;  // X....
    font[{4'd3, 3'd3}] = 5'b00001;  // X....
    font[{4'd3, 3'd4}] = 5'b00001;  // X....
    font[{4'd3, 3'd5}] = 5'b10001;  // X...X
    font[{4'd3, 3'd6}] = 5'b01110;  // .XXX.

    // --- Glyph 4: O ---
    font[{4'd4, 3'd0}] = 5'b01110;  // .XXX.
    font[{4'd4, 3'd1}] = 5'b10001;  // X...X
    font[{4'd4, 3'd2}] = 5'b10001;  // X...X
    font[{4'd4, 3'd3}] = 5'b10001;  // X...X
    font[{4'd4, 3'd4}] = 5'b10001;  // X...X
    font[{4'd4, 3'd5}] = 5'b10001;  // X...X
    font[{4'd4, 3'd6}] = 5'b01110;  // .XXX.

    // --- Glyph 5: N ---
    font[{4'd5, 3'd0}] = 5'b10001;  // X...X
    font[{4'd5, 3'd1}] = 5'b10011;  // XX..X
    font[{4'd5, 3'd2}] = 5'b10101;  // X.X.X
    font[{4'd5, 3'd3}] = 5'b11001;  // X..XX
    font[{4'd5, 3'd4}] = 5'b10001;  // X...X
    font[{4'd5, 3'd5}] = 5'b10001;  // X...X
    font[{4'd5, 3'd6}] = 5'b10001;  // X...X

    // --- Glyph 6: M ---
    font[{4'd6, 3'd0}] = 5'b10001;  // X...X
    font[{4'd6, 3'd1}] = 5'b11011;  // XX.XX
    font[{4'd6, 3'd2}] = 5'b10101;  // X.X.X
    font[{4'd6, 3'd3}] = 5'b10001;  // X...X
    font[{4'd6, 3'd4}] = 5'b10001;  // X...X
    font[{4'd6, 3'd5}] = 5'b10001;  // X...X
    font[{4'd6, 3'd6}] = 5'b10001;  // X...X

    // --- Glyph 7: T ---
    font[{4'd7, 3'd0}] = 5'b11111;  // XXXXX
    font[{4'd7, 3'd1}] = 5'b00100;  // ..X..
    font[{4'd7, 3'd2}] = 5'b00100;  // ..X..
    font[{4'd7, 3'd3}] = 5'b00100;  // ..X..
    font[{4'd7, 3'd4}] = 5'b00100;  // ..X..
    font[{4'd7, 3'd5}] = 5'b00100;  // ..X..
    font[{4'd7, 3'd6}] = 5'b00100;  // ..X..

    // --- Glyph 8: blank — all-zero rows (initializer loop fills these) ---
  end

  // -------------------------------------------------------------------
  // Pixel evaluation
  // -------------------------------------------------------------------
  wire [4:0] glyph_row_data = font[{cur_glyph, char_row}];

  // LSB-first: bit char_col is the pixel for that column.
  // Columns 5..7 are the inter-character gap (always dark).
  wire glyph_pixel = (char_col <= 3'd4) && glyph_row_data[char_col];

  assign active = in_y_band;
  assign pixel  = in_y_band && glyph_pixel;

endmodule
