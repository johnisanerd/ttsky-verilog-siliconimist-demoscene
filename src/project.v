/*
 * Copyright (c) 2024 Tiny Tapeout LTD
 * SPDX-License-Identifier: Apache-2.0
 * Original VGA template by Uri Shaked.
 * Siliconimist demoscene customization.
 */

`default_nettype none

parameter LOGO_SIZE = 128;       // Sprite size in pixels (square)
parameter DISPLAY_WIDTH = 640;   // VGA display width
parameter DISPLAY_HEIGHT = 480;  // VGA display height

`define COLOR_WHITE 3'd7

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
  wire cfg_color = ui_in[1];  // color-cycle the sprite ink (else white)
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

  wire _unused_ok = &{ena, ui_in[7:3], uio_in};

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
  reg  [2:0] color_index;
  reg  [9:0] frame_counter;

  wire        pixel_value;
  wire [5:0]  color;

  wire [9:0] x = pix_x - logo_left;
  wire [9:0] y = pix_y - logo_top;
  wire logo_pixels = cfg_tile || (x[9:7] == 0 && y[9:7] == 0);

  bitmap_rom rom1 (
      .x(x[6:0]),
      .y(y[6:0]),
      .pixel(pixel_value)
  );

  // Rasterbar background: 16-pixel-tall bands cycling vertically with frame_counter
  wire [2:0] bar_index = pix_y[6:4] + frame_counter[5:3];

  // Sprite ink shows logo color on top of rasterbars; transparent pixels show bars
  wire show_logo_ink = logo_pixels && pixel_value;
  wire [2:0] active_index =
      show_logo_ink ? (cfg_color ? color_index : `COLOR_WHITE)
                    : bar_index;

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
      color_index   <= 0;
      frame_counter <= 0;
      prev_y        <= 0;
    end else begin
      prev_y <= pix_y;
      if (frame_tick) begin
        frame_counter <= frame_counter + 1;
        logo_left     <= logo_left + (dir_x ? 1 : -1);
        logo_top      <= logo_top  + (dir_y ? 1 : -1);
        if (logo_left - 1 == 0 && !dir_x) begin
          dir_x       <= 1;
          color_index <= color_index + 1;
        end
        if (logo_left + 1 == DISPLAY_WIDTH - LOGO_SIZE && dir_x) begin
          dir_x       <= 0;
          color_index <= color_index + 1;
        end
        if (logo_top - 1 == 0 && !dir_y) begin
          dir_y       <= 1;
          color_index <= color_index + 1;
        end
        if (logo_top + 1 == DISPLAY_HEIGHT - LOGO_SIZE && dir_y) begin
          dir_y       <= 0;
          color_index <= color_index + 1;
        end
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
