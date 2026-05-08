/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Two-voice + drums chiptune for the Siliconimist demo. Architecture
 * adapted from Renaldas Zioma & Erik Hemming's "Drop" demo
 * (https://github.com/rejunity/tt08-vga-drop) which originally appeared
 * on tt08. Copyright (c) 2024 R. Zioma & E. Hemming for the original.
 *
 * Why this design:
 *   - Oscillator counters tick at the VGA *line* rate (~31.5 kHz), not
 *     at clk (25 MHz). That gives 8-bit divisors that map directly onto
 *     standard chiptune note tables, and keeps the counters small.
 *   - Voices are mixed by *time-division* across the scanline: each voice
 *     is gated to a fixed x-range and the audio output is OR(voices).
 *     Sampled at clk and low-passed by the TT Audio Pmod, this reads as
 *     polyphony without XOR-mixing artifacts. A voice's loudness is set
 *     by how wide its x-window is.
 *   - Envelopes are free: 5'd31 - timer[4:0] == ~timer[4:0]. Multiplying
 *     the envelope by a power of two gives a sliding window threshold,
 *     so when env=0 the voice's window has zero width and the voice is
 *     silent. That's the attack/decay shape that was missing from the
 *     previous "raw 1-bit square forever" design.
 *   - Drums: 60 Hz "kick" comes free from pix_y < 262 (half-frame ON,
 *     half-frame OFF -> one pulse per frame). Snare is a 13-bit LFSR
 *     gated to the backbeat. No DSP needed.
 *
 * Lead voice plays Korobeiniki (Tetris Type A theme) from the Wikipedia
 * LilyPond transcription, 96 eighth-notes / 12 measures, 16 frames per
 * eighth-note (~112 BPM, song loops every ~25.6 s). Bass voice plays the
 * chord root (V/i = E/A) per measure.
 *
 * Output is wired to uio[7] for the TT Audio Pmod
 * (https://github.com/MichaelBell/tt-audio-pmod).
 */

`default_nettype none

module chiptune (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       frame_tick,   // one-cycle pulse per VGA frame
    input  wire [9:0] pix_x,        // VGA horizontal position
    input  wire [9:0] pix_y,        // VGA vertical position
    input  wire       mute,
    output wire       audio
);

  // 8-bit divisors. With ~31.5 kHz line rate, half_period = (note_freq+1)
  // line cycles, so freq ~= 31500 / (2 * (note_freq + 1)). Values come
  // from the published Drop note table; pitch is within ~2-3% of equal
  // temperament which is well within "chiptune" tolerance.
  localparam [7:0] NOTE_E3  = 8'd95;   // ~164 Hz
  localparam [7:0] NOTE_A3  = 8'd72;   // ~220 Hz
  localparam [7:0] NOTE_E4  = 8'd48;   // ~322 Hz
  localparam [7:0] NOTE_GS4 = 8'd38;   // ~404 Hz
  localparam [7:0] NOTE_A4  = 8'd36;   // ~426 Hz
  localparam [7:0] NOTE_B4  = 8'd32;   // ~477 Hz
  localparam [7:0] NOTE_C5  = 8'd30;   // ~508 Hz
  localparam [7:0] NOTE_D5  = 8'd27;   // ~563 Hz
  localparam [7:0] NOTE_E5  = 8'd24;   // ~630 Hz
  localparam [7:0] NOTE_F5  = 8'd23;   // ~656 Hz
  localparam [7:0] NOTE_G5  = 8'd20;   // ~750 Hz
  localparam [7:0] NOTE_A5  = 8'd18;   // ~829 Hz

  localparam SONG_LEN        = 96;
  localparam FRAMES_PER_STEP = 16;     // 60 Hz / 16 = 3.75 eighth-notes/s = 112 BPM

  //
  // Frame counter (12-bit, free-running on frame_tick). Drives song
  // progression, drum gating, and envelope shapes.
  //
  reg [11:0] frame_counter;
  always @(posedge clk) begin
    if (~rst_n)            frame_counter <= 0;
    else if (frame_tick)   frame_counter <= frame_counter + 1'b1;
  end
  wire [11:0] timer = frame_counter;

  //
  // Song step counter: 16 frames per eighth-note slot, 96 slots per loop.
  // Korobeiniki has 96 slots (12 * 8) which is not a power of 2, so we
  // use an explicit mod-96 wrap rather than a bit-slice trick.
  //
  reg [3:0] frames_in_step;
  reg [6:0] song_step;
  always @(posedge clk) begin
    if (~rst_n) begin
      frames_in_step <= 0;
      song_step      <= 0;
    end else if (frame_tick) begin
      if (frames_in_step == FRAMES_PER_STEP - 1) begin
        frames_in_step <= 0;
        if (song_step == SONG_LEN - 1) song_step <= 0;
        else                            song_step <= song_step + 1'b1;
      end else begin
        frames_in_step <= frames_in_step + 1'b1;
      end
    end
  end

  //
  // Korobeiniki song table: 4-bit pitch index per slot.
  // 0=E4 1=G#4 2=A4 3=B4 4=C5 5=D5 6=E5 7=F5 8=G5 9=A5
  //
  reg [3:0] song [0:SONG_LEN-1];
  initial begin
    // m1: E4(dq) G#4(e) B4(q) G#4(e) E4(e)
    song[ 0]=4'd0; song[ 1]=4'd0; song[ 2]=4'd0; song[ 3]=4'd1;
    song[ 4]=4'd3; song[ 5]=4'd3; song[ 6]=4'd1; song[ 7]=4'd0;
    // m2: A4(dq) C5(e) E5(q) D5(e) C5(e)
    song[ 8]=4'd2; song[ 9]=4'd2; song[10]=4'd2; song[11]=4'd4;
    song[12]=4'd6; song[13]=4'd6; song[14]=4'd5; song[15]=4'd4;
    // m3: B4(dq) C5(e) D5(q) E5(q)
    song[16]=4'd3; song[17]=4'd3; song[18]=4'd3; song[19]=4'd4;
    song[20]=4'd5; song[21]=4'd5; song[22]=4'd6; song[23]=4'd6;
    // m4: C5(q) A4(q) A4(h)
    song[24]=4'd4; song[25]=4'd4; song[26]=4'd2; song[27]=4'd2;
    song[28]=4'd2; song[29]=4'd2; song[30]=4'd2; song[31]=4'd2;
    // m5: F5(dq) G5(e) A5(q) G5(e) F5(e)
    song[32]=4'd7; song[33]=4'd7; song[34]=4'd7; song[35]=4'd8;
    song[36]=4'd9; song[37]=4'd9; song[38]=4'd8; song[39]=4'd7;
    // m6: E5(dq) F5(e) E5(q) D5(e) C5(e)
    song[40]=4'd6; song[41]=4'd6; song[42]=4'd6; song[43]=4'd7;
    song[44]=4'd6; song[45]=4'd6; song[46]=4'd5; song[47]=4'd4;
    // m7: B4(dq) C5(e) D5(q) E5(q)
    song[48]=4'd3; song[49]=4'd3; song[50]=4'd3; song[51]=4'd4;
    song[52]=4'd5; song[53]=4'd5; song[54]=4'd6; song[55]=4'd6;
    // m8: C5(q) A4(q) A4(h)
    song[56]=4'd4; song[57]=4'd4; song[58]=4'd2; song[59]=4'd2;
    song[60]=4'd2; song[61]=4'd2; song[62]=4'd2; song[63]=4'd2;
    // m5..m8 repeat
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
  wire [3:0] measure   = song_step[6:3];

  //
  // Pitch -> divisor lookup for lead and bass.
  //
  reg [7:0] lead_freq;
  always @(*) begin
    case (cur_pitch)
      4'd0:    lead_freq = NOTE_E4;
      4'd1:    lead_freq = NOTE_GS4;
      4'd2:    lead_freq = NOTE_A4;
      4'd3:    lead_freq = NOTE_B4;
      4'd4:    lead_freq = NOTE_C5;
      4'd5:    lead_freq = NOTE_D5;
      4'd6:    lead_freq = NOTE_E5;
      4'd7:    lead_freq = NOTE_F5;
      4'd8:    lead_freq = NOTE_G5;
      4'd9:    lead_freq = NOTE_A5;
      default: lead_freq = NOTE_A4;
    endcase
  end

  // Bass: A-minor V/i cadence -- E (V chord root) on measures 0/2/6/10,
  // A (i chord root) elsewhere. Encoded as a 6-minterm case.
  reg [7:0] bass_freq;
  always @(*) begin
    case (measure)
      4'd0, 4'd2, 4'd6, 4'd10: bass_freq = NOTE_E3;
      default:                 bass_freq = NOTE_A3;
    endcase
  end

  //
  // Lead oscillator: 8-bit counter ticking once per VGA scanline.
  //
  reg [7:0] lead_counter;
  reg       lead;
  always @(posedge clk) begin
    if (~rst_n) begin
      lead_counter <= 0;
      lead         <= 0;
    end else if (pix_x == 10'd0) begin
      if (lead_counter > lead_freq) begin
        lead_counter <= 0;
        lead         <= ~lead;
      end else begin
        lead_counter <= lead_counter + 1'b1;
      end
    end
  end

  //
  // Bass oscillator: 8-bit counter at line rate (E3=95 fits in 8 bits).
  //
  reg [7:0] bass_counter;
  reg       bass;
  always @(posedge clk) begin
    if (~rst_n) begin
      bass_counter <= 0;
      bass         <= 0;
    end else if (pix_x == 10'd0) begin
      if (bass_counter > bass_freq) begin
        bass_counter <= 0;
        bass         <= ~bass;
      end else begin
        bass_counter <= bass_counter + 1'b1;
      end
    end
  end

  //
  // 13-bit LFSR for snare noise. Tap pattern from the Drop demo; the
  // "+1'b1" at the end is just an XOR with 1 (avoids the all-zeros
  // lock-up state without needing an explicit guard).
  //
  reg [12:0] lfsr;
  wire feedback = lfsr[12] ^ lfsr[8] ^ lfsr[2] ^ lfsr[0] + 1'b1;
  always @(posedge clk) begin
    if (~rst_n) lfsr <= 13'h1;
    else        lfsr <= {lfsr[11:0], feedback};
  end

  // Slow the LFSR's effective rate down so noise reads as a snare hit
  // rather than a hiss: only mix lfsr's parity into `noise` every third
  // line. Counter value 1 here matches the Drop tuning.
  wire       noise_src = ^lfsr;
  reg  [2:0] noise_counter;
  reg        noise;
  always @(posedge clk) begin
    if (~rst_n) begin
      noise_counter <= 0;
      noise         <= 0;
    end else if (pix_x == 10'd0) begin
      if (noise_counter > 3'd1) begin
        noise_counter <= 0;
        noise         <= noise ^ noise_src;
      end else begin
        noise_counter <= noise_counter + 1'b1;
      end
    end
  end

  //
  // Envelopes (free, since 31 - X[4:0] == ~X[4:0]).
  //   envA: 32-frame ramp-down (~533 ms decay), drives kick.
  //   envB: 16-frame ramp-down (~267 ms decay), drives snare and lead.
  //
  wire [4:0] envA = ~timer[4:0];
  wire [4:0] envB = ~{timer[3:0], 1'b0};

  // Drum-time gating. With 16 frames per eighth-note, timer[5:4]==2'b10
  // selects eighth-notes 2-3 of every 4-eighth cycle, which lines up to
  // beats 2 and 4 of the Korobeiniki measure -- standard backbeat snare.
  wire        beats_1_3  = (timer[5:4] == 2'b10);
  // 60 Hz pulse train (one half-frame pulse per VGA frame) for the kick.
  wire        square60hz = (pix_y < 10'd262);

  //
  // Time-division mix. Each voice owns a slice of the scanline; final
  // audio = OR of all voices. The voice envelope shows up as window
  // width: env=0 -> zero-wide window -> voice silent for that frame.
  //
  // x-windows (640-px line):
  //   kick:  [0,           envA*4)              up to ~124 px wide
  //   snare: [128,    128 + envB*4)             up to ~252 px right edge
  //   lead:  [256,    256 + envB*8)             up to ~504 px right edge
  //   bass:  [512, 544 or 640)                  ducks on backbeats so the
  //                                             snare doesn't compete
  //
  wire kick    = square60hz & (pix_x          < {3'b000, envA, 2'b00});
  wire snare_v = noise      & (pix_x >= 10'd128) &
                              (pix_x          < (10'd128 + {3'b000, envB, 2'b00}));
  wire lead_v  = lead       & (pix_x >= 10'd256) &
                              (pix_x          < (10'd256 + {2'b00, envB, 3'b000}));
  wire bass_v  = bass       & (pix_x >= 10'd512) &
                              (pix_x          < (beats_1_3 ? 10'd544 : 10'd640));

  // Snare only on the backbeat; everything else plays whenever its
  // envelope window is non-zero.
  wire snare_g = snare_v & beats_1_3;
  wire mixed   = kick | snare_g | bass_v | lead_v;

  assign audio = mute ? 1'b0 : mixed;

endmodule
