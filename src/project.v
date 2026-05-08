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

  // Rasterbars: 16-pixel-tall bands rotating orange -> white -> blue -> ...
  // mod 3. Adding frame_counter to pix_y scrolls the whole pattern upward at
  // 1 pixel per VGA frame (~60 px/s). To scroll faster, replace `frame_counter`
  // below with e.g. `(frame_counter << 1)`; to scroll downward, subtract.
  wire [9:0] scroll_y  = pix_y + frame_counter;
  wire [4:0] bar_phase = scroll_y[8:4];
  reg  [1:0] bar_state;
  always @(*) begin
    case (bar_phase)
      5'd0,5'd3,5'd6,5'd9, 5'd12,5'd15,5'd18,5'd21,5'd24,5'd27,5'd30: bar_state = `PAL_ORANGE;
      5'd1,5'd4,5'd7,5'd10,5'd13,5'd16,5'd19,5'd22,5'd25,5'd28,5'd31: bar_state = `PAL_WHITE;
      5'd2,5'd5,5'd8,5'd11,5'd14,5'd17,5'd20,5'd23,5'd26,5'd29:       bar_state = `PAL_BLUE;
      default:                                                         bar_state = `PAL_ORANGE;
    endcase
  end

  // Sprite ink is always black; everywhere else uses the rotating bar color.
  wire show_logo_ink = logo_pixels && pixel_value;
  wire [1:0] active_index = show_logo_ink ? `PAL_BLACK : bar_state;

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
