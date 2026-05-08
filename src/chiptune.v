/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Korobeiniki melody (square wave), same song ROM as earlier Siliconimist
 * demos. Drive is intentionally *simple* compared to Drop-style demos:
 *
 * Problem seen in simulation (capture_audio): time-division across the scan
 * line (OR of kick/snare/bass gates on narrow pix_x slices) pushes most of the
 * "audio" energy into ~microsecond bursts repeating at line rate (~15–31 kHz
 * modulation). Playback at capture rate (~98 kHz) without the TT Audio Pmod
 * low-pass that integrates those bursts reads as chopped / buzzy — and the
 * ~16-frame lead envelope collapsing envB visibly drops per-frame duty from
 * ~31% to ~14% in the regression log while the melody is still playing.
 *
 * This path: toggle a single square wave at the pixel-clock rate (half-period
 * = note_div+1 clocks). envelope = continuously on for the melody line.
 * Phase-reset when the pitch changes to avoid divisor-swap clicks.
 *
 * divisors tuned for clk = 25.175 MHz (Tiny Tapeout VGA clock): half_period +
 *     1 cycles per half wave  => f = clk/(2*(div+1))
 */

`default_nettype none

module chiptune (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       frame_tick,  // once per VGA frame (~60 Hz)
    input  wire       mute,
    output wire       audio
);

  localparam FRAMES_PER_STEP = 16;  // 60/16 Hz per eighth = 112.5 BPM
  localparam SONG_LEN        = 96;

  reg [3:0] frames_in_step;
  reg [6:0] song_step;
  always @(posedge clk) begin
    if (~rst_n) begin
      frames_in_step <= 0;
      song_step      <= 0;
    end else if (frame_tick) begin
      if (frames_in_step == FRAMES_PER_STEP - 1) begin
        frames_in_step <= 0;
        if (song_step == SONG_LEN - 1)
          song_step <= 0;
        else
          song_step <= song_step + 1'b1;
      end else begin
        frames_in_step <= frames_in_step + 1'b1;
      end
    end
  end

  // Pitches 0=E4 … 9=A5 (equal temperament)
  reg [3:0] song [0:SONG_LEN-1];
  initial begin
    song[ 0]=4'd0; song[ 1]=4'd0; song[ 2]=4'd0; song[ 3]=4'd1;
    song[ 4]=4'd3; song[ 5]=4'd3; song[ 6]=4'd1; song[ 7]=4'd0;
    song[ 8]=4'd2; song[ 9]=4'd2; song[10]=4'd2; song[11]=4'd4;
    song[12]=4'd6; song[13]=4'd6; song[14]=4'd5; song[15]=4'd4;
    song[16]=4'd3; song[17]=4'd3; song[18]=4'd3; song[19]=4'd4;
    song[20]=4'd5; song[21]=4'd5; song[22]=4'd6; song[23]=4'd6;
    song[24]=4'd4; song[25]=4'd4; song[26]=4'd2; song[27]=4'd2;
    song[28]=4'd2; song[29]=4'd2; song[30]=4'd2; song[31]=4'd2;
    song[32]=4'd7; song[33]=4'd7; song[34]=4'd7; song[35]=4'd8;
    song[36]=4'd9; song[37]=4'd9; song[38]=4'd8; song[39]=4'd7;
    song[40]=4'd6; song[41]=4'd6; song[42]=4'd6; song[43]=4'd7;
    song[44]=4'd6; song[45]=4'd6; song[46]=4'd5; song[47]=4'd4;
    song[48]=4'd3; song[49]=4'd3; song[50]=4'd3; song[51]=4'd4;
    song[52]=4'd5; song[53]=4'd5; song[54]=4'd6; song[55]=4'd6;
    song[56]=4'd4; song[57]=4'd4; song[58]=4'd2; song[59]=4'd2;
    song[60]=4'd2; song[61]=4'd2; song[62]=4'd2; song[63]=4'd2;
    song[64]=4'd7; song[65]=4'd7; song[66]=4'd7; song[67]=4'd8;
    song[68]=4'd9; song[69]=4'd9; song[70]=4'd8; song[71]=4'd7;
    song[72]=4'd6; song[73]=4'd6; song[74]=4'd6; song[75]=4'd7;
    song[76]=4'd6; song[77]=4'd6; song[78]=4'd5; song[79]=4'd4;
    song[80]=4'd3; song[81]=4'd3; song[82]=4'd3; song[83]=4'd4;
    song[84]=4'd5; song[85]=4'd5; song[86]=4'd6; song[87]=4'd6;
    song[88]=4'd4; song[89]=4'd4; song[90]=4'd2; song[91]=4'd2;
    song[92]=4'd2; song[93]=4'd2; song[94]=4'd2; song[95]=4'd2;
  end

  wire [3:0] cur_pitch = song[song_step];

  reg [15:0] note_div;
  always @(*) begin
    case (cur_pitch)
      // div = clk/(2*f) - 1, clk = 25_175_000
      4'd0:    note_div = 16'd38200;  // E4  ~329.6 Hz
      4'd1:    note_div = 16'd30306;  // G#4 ~415.3 Hz
      4'd2:    note_div = 16'd28607;  // A4  ~440.0 Hz
      4'd3:    note_div = 16'd25486;  // B4  ~493.9 Hz
      4'd4:    note_div = 16'd24055;  // C5  ~523.3 Hz
      4'd5:    note_div = 16'd21431;  // D5  ~587.4 Hz
      4'd6:    note_div = 16'd19090;  // E5  ~659.3 Hz
      4'd7:    note_div = 16'd18017;  // F5  ~698.5 Hz
      4'd8:    note_div = 16'd16054;  // G5  ~784.2 Hz
      4'd9:    note_div = 16'd14302;  // A5  ~880.0 Hz
      default: note_div = 16'd28607;
    endcase
  end

  reg [3:0] prev_pitch;
  wire pitch_changed = (cur_pitch != prev_pitch);

  reg [15:0] tone_counter;
  reg        square;

  always @(posedge clk) begin
    if (~rst_n) begin
      prev_pitch <= 0;
      tone_counter <= 0;
      square <= 0;
    end else begin
      prev_pitch <= cur_pitch;
      if (pitch_changed) begin
        tone_counter <= note_div;
        square       <= 1'b0;
      end else if (tone_counter == 0) begin
        tone_counter <= note_div;
        square       <= ~square;
      end else begin
        tone_counter <= tone_counter - 1'b1;
      end
    end
  end

  assign audio = mute ? 1'b0 : square;

endmodule
