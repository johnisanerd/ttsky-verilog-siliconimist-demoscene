/*
 * Copyright (c) 2024 Tiny Tapeout LTD
 * SPDX-License-Identifier: Apache-2.0
 * Original VGA template by Uri Shaked.
 * Siliconimist demoscene customization.
 */

`default_nettype none

parameter LOGO_SIZE = 128;        // Native (ROM) sprite size in pixels (square)
parameter LOGO_SCALE_LOG2 = 1;    // On-screen scale: 0 = 1x (128px), 1 = 2x (256px),
                                  // 2 = 4x (512px). 4x does NOT fit a 480-line display.
parameter DISPLAY_WIDTH = 640;
parameter DISPLAY_HEIGHT = 480;

localparam EFFECTIVE_LOGO_SIZE = LOGO_SIZE << LOGO_SCALE_LOG2;

// Palette indices (kept in sync with src/palette.v)
`define PAL_ORANGE 2'd0
`define PAL_WHITE  2'd1
`define PAL_BLUE   2'd2
`define PAL_BLACK  2'd3

module tt_um_siliconimist (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs (TinyVGA Pmod)
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path (uio_out[7] = PWM audio)
    output wire [7:0] uio_oe,   // IOs: Enable path
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  // VGA signals
  wire hsync;
  wire vsync;
  reg [1:0] R;
  reg [1:0] G;
  reg [1:0] B;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  // Configuration switches on ui_in
  wire cfg_tile  = ui_in[0];  // tile the sprite full-screen (debug)
  wire mute      = ui_in[2];  // force PWM audio low

  // TinyVGA Pmod pinout on uo_out (https://github.com/mole99/tiny-vga):
  //   uo[0]=R1 uo[1]=G1 uo[2]=B1 uo[3]=vsync
  //   uo[4]=R0 uo[5]=G0 uo[6]=B0 uo[7]=hsync
  assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  // TT Audio Pmod pinout (https://github.com/MichaelBell/tt-audio-pmod):
  // mono audio on uio[7]; lower row uio[6:0] left passthrough-friendly.
  wire audio_out;
  assign uio_out = {audio_out, 7'b0000000};
  assign uio_oe  = 8'b1000_0000;

  wire _unused_ok = &{ena, ui_in[7:3], ui_in[1], uio_in};

  reg [9:0] prev_y;

  hvsync_generator vga_sync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
  );

  reg  [9:0] logo_left;
  reg  [9:0] logo_top;
  reg        dir_x;
  reg        dir_y;
  reg  [9:0] frame_counter;

  wire        pixel_value;
  wire [5:0]  color;

  wire [9:0] x = pix_x - logo_left;
  wire [9:0] y = pix_y - logo_top;
  wire logo_pixels = cfg_tile ||
      (x < EFFECTIVE_LOGO_SIZE && y < EFFECTIVE_LOGO_SIZE);

  // Pixel-double the sprite by dropping LOGO_SCALE_LOG2 low bits before the
  // ROM lookup; one ROM pixel covers a (2^LOGO_SCALE_LOG2) screen square.
  bitmap_rom rom1 (
      .x(x[6+LOGO_SCALE_LOG2:LOGO_SCALE_LOG2]),
      .y(y[6+LOGO_SCALE_LOG2:LOGO_SCALE_LOG2]),
      .pixel(pixel_value)
  );

  // Rasterbars: 32-pixel-tall bands rotating orange -> white -> blue -> ...
  // Scroll at 2px/frame (frame_counter*2) so apparent speed matches the old
  // 16px-bar / 1px-per-frame design.  9-bit arithmetic wraps naturally.
  wire [8:0] scroll_y   = pix_y[8:0] + {frame_counter[7:0], 1'b0};
  wire [3:0] bar_phase  = scroll_y[8:5];   // which 32-px band (0-15)
  wire [4:0] pos_in_bar = scroll_y[4:0];   // position within band (0-31)

  reg  [1:0] bar_state;
  always @(*) begin
    case (bar_phase)
      4'd0,4'd3,4'd6,4'd9, 4'd12,4'd15: bar_state = `PAL_ORANGE;
      4'd1,4'd4,4'd7,4'd10,4'd13:       bar_state = `PAL_WHITE;
      4'd2,4'd5,4'd8,4'd11,4'd14:       bar_state = `PAL_BLUE;
      default:                           bar_state = `PAL_ORANGE;
    endcase
  end

  // 4x4 Bayer ordered-dither matrix indexed by (pix_y[1:0], pix_x[1:0]).
  // The TinyVGA Pmod is 2 bits per channel (4 levels per channel), so true
  // smooth gradients are impossible -- we fake intermediate brightnesses
  // between bar_state and PAL_BLACK with a stable 4x4 stipple instead.
  reg [3:0] bayer;
  always @(*) begin
    case ({pix_y[1:0], pix_x[1:0]})
      4'b00_00: bayer = 4'd0;   4'b00_01: bayer = 4'd8;
      4'b00_10: bayer = 4'd2;   4'b00_11: bayer = 4'd10;
      4'b01_00: bayer = 4'd12;  4'b01_01: bayer = 4'd4;
      4'b01_10: bayer = 4'd14;  4'b01_11: bayer = 4'd6;
      4'b10_00: bayer = 4'd3;   4'b10_01: bayer = 4'd11;
      4'b10_10: bayer = 4'd1;   4'b10_11: bayer = 4'd9;
      4'b11_00: bayer = 4'd15;  4'b11_01: bayer = 4'd7;
      4'b11_10: bayer = 4'd13;  4'b11_11: bayer = 4'd5;
    endcase
  end

  // Center-peaked brightness: dark at both edges, bright at the bar center.
  // pos_in_bar runs 0..31; the MSB splits it into two halves and the lower
  // 4 bits ramp 0→15 then back 15→0, giving a symmetric "neon tube" glow.
  wire [3:0] brightness = pos_in_bar[4] ? (4'd15 - pos_in_bar[3:0])
                                        :              pos_in_bar[3:0];
  wire [1:0] dithered_bar = (brightness > bayer) ? bar_state : `PAL_BLACK;

  // Logo ink is white so it stands out against all three bar colors.
  wire show_logo_ink = logo_pixels && pixel_value;

  // Scrolling "SILICONIMIST" marquee at the bottom of the screen.
  // scroll_x advances 1 pixel per frame (60 px/s); the 256-px tiling period
  // repeats ~2.5× across the 640-pixel width for a continuous marquee effect.
  wire text_active;
  wire text_pixel;
  text_scroller marquee (
      .pix_x  (pix_x),
      .pix_y  (pix_y),
      .scroll (frame_counter),
      .pixel  (text_pixel),
      .active (text_active)
  );

  // Compositing priority (highest to lowest):
  //   1. Logo sprite (white ink over everything)
  //   2. Scrolling text marquee (orange, demoscene branding)
  //   3. Dithered rasterbars (background)
  wire [1:0] active_index = show_logo_ink ? `PAL_WHITE  :
                            text_pixel    ? `PAL_ORANGE :
                                            dithered_bar;

  palette palette_inst (
      .color_index(active_index),
      .rrggbb(color)
  );

  always @(posedge clk) begin
    if (~rst_n) begin
      R <= 0;
      G <= 0;
      B <= 0;
    end else begin
      R <= 0;
      G <= 0;
      B <= 0;
      if (video_active) begin
        R <= color[5:4];
        G <= color[3:2];
        B <= color[1:0];
      end
    end
  end

  // One-pulse-per-frame tick used by both bouncer and audio note advance
  wire frame_tick = (pix_y == 0) && (prev_y != pix_y);

  always @(posedge clk) begin
    if (~rst_n) begin
      logo_left     <= 200;
      logo_top      <= 200;
      dir_y         <= 0;
      dir_x         <= 1;
      frame_counter <= 0;
      prev_y        <= 0;
    end else begin
      prev_y <= pix_y;
      if (frame_tick) begin
        frame_counter <= frame_counter + 1;
        logo_left     <= logo_left + (dir_x ? 1 : -1);
        logo_top      <= logo_top  + (dir_y ? 1 : -1);
        if (logo_left - 1 == 0 && !dir_x) dir_x <= 1;
        if (logo_left + 1 == DISPLAY_WIDTH  - EFFECTIVE_LOGO_SIZE && dir_x) dir_x <= 0;
        if (logo_top  - 1 == 0 && !dir_y) dir_y <= 1;
        if (logo_top  + 1 == DISPLAY_HEIGHT - EFFECTIVE_LOGO_SIZE && dir_y) dir_y <= 0;
      end
    end
  end

  chiptune audio_inst (
      .clk(clk),
      .rst_n(rst_n),
      .frame_tick(frame_tick),
      .mute(mute),
      .audio(audio_out)
  );

endmodule
