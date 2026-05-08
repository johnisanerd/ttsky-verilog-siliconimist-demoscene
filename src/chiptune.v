/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tiny chiptune square-wave synth for the Siliconimist demo.
 *
 * Plays "Korobeiniki" (the Tetris Type A theme) as a 1-bit square wave.
 * The melody is the Wikipedia LilyPond transcription:
 *   https://en.wikipedia.org/wiki/Korobeiniki
 *   m1: e4. gis8 b4 gis8 e8     m2: a4. c8 e4 d8 c8
 *   m3: b4. c8 d4 e4            m4: c4 a4 a2
 *   \repeat volta 2 {
 *   m5: f'4. g8 a4 g8 f8        m6: e4. f8 e4 d8 c8
 *   m7: b4. c8 d4 e4            m8: c4 a4 a2 }
 *
 * Stored as 96 eighth-note slots (12 measures * 8) with a 4-bit pitch
 * index per slot. At 12 frame_tick pulses per slot (~150 BPM at 60 Hz
 * vsync), the song loops every ~19.2 s.
 *
 * Output is a 1-bit square wave at the current note's fundamental, fed
 * to the TT Audio Pmod (https://github.com/MichaelBell/tt-audio-pmod)
 * on uio[7] per the TT pinouts spec (https://tinytapeout.com/specs/pinouts/).
 *
 * Half-period divisors are sized for the 25.175 MHz VGA pixel clock:
 *   note_div = floor(clk_freq / (2 * note_freq)) - 1
 *   so the toggle period is (note_div + 1) clk cycles.
 */

`default_nettype none

module chiptune (
    input  wire clk,
    input  wire rst_n,
    input  wire frame_tick,  // one-cycle pulse per VGA frame (~60 Hz)
    input  wire mute,
    output wire audio
);

  localparam FRAMES_PER_STEP = 12;  // 60 Hz / 12 = 5 eighth-notes/s = 150 BPM
  localparam SONG_LEN        = 96;  // 12 measures * 8 eighth-note slots

  reg [3:0] frame_in_step;          // 0..11
  reg [6:0] song_step;              // 0..95

  // Song table: one 4-bit pitch index per eighth-note slot.
  // Pitches: 0=E4 1=G#4 2=A4 3=B4 4=C5 5=D5 6=E5 7=F5 8=G5 9=A5
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

  // Pitch -> half-period divisor for a 25.175 MHz clock.
  reg [15:0] note_div;
  always @(*) begin
    case (cur_pitch)
      4'd0: note_div = 16'd38184;  // E4   329.63 Hz
      4'd1: note_div = 16'd30307;  // G#4  415.30 Hz
      4'd2: note_div = 16'd28607;  // A4   440.00 Hz
      4'd3: note_div = 16'd25485;  // B4   493.88 Hz
      4'd4: note_div = 16'd24055;  // C5   523.25 Hz
      4'd5: note_div = 16'd21433;  // D5   587.33 Hz
      4'd6: note_div = 16'd19091;  // E5   659.26 Hz
      4'd7: note_div = 16'd18020;  // F5   698.46 Hz
      4'd8: note_div = 16'd16054;  // G5   783.99 Hz
      4'd9: note_div = 16'd14303;  // A5   880.00 Hz
      default: note_div = 16'd28607;
    endcase
  end

  reg [15:0] tone_counter;
  reg        square;

  always @(posedge clk) begin
    if (~rst_n) begin
      frame_in_step <= 0;
      song_step     <= 0;
      tone_counter  <= 0;
      square        <= 0;
    end else begin
      if (frame_tick) begin
        if (frame_in_step == FRAMES_PER_STEP - 1) begin
          frame_in_step <= 0;
          if (song_step == SONG_LEN - 1)
            song_step <= 0;
          else
            song_step <= song_step + 1'b1;
        end else begin
          frame_in_step <= frame_in_step + 1'b1;
        end
      end

      if (tone_counter == 0) begin
        tone_counter <= note_div;
        square       <= ~square;
      end else begin
        tone_counter <= tone_counter - 1'b1;
      end
    end
  end

  assign audio = mute ? 1'b0 : square;

endmodule
