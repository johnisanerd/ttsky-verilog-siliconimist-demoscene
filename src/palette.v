/*
 * Copyright (c) 2024 Tiny Tapeout LTD
 * SPDX-License-Identifier: Apache-2.0
 * Original by Uri Shaked; Siliconimist palette overlay.
 *
 * 2-bit-per-channel TinyVGA encodes each level as one of {0, 85, 170, 255},
 * so brand colors are quantized to the closest 6-bit RRGGBB value.
 */

`default_nettype none

module palette (
    input  wire [1:0] color_index,
    output wire [5:0] rrggbb
);

  reg [5:0] palette[3:0];

  initial begin
    palette[0] = 6'b110100;  // orange   #FF6719 -> closest 2-bit ~#FF5500
    palette[1] = 6'b111111;  // white    #FFFFFF
    palette[2] = 6'b000001;  // blue     #14223C -> closest 2-bit ~#000055
    palette[3] = 6'b000000;  // black    used for the logo ink
  end

  assign rrggbb = palette[color_index];

endmodule
