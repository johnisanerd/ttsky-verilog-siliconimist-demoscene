/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tiny chiptune square-wave synth for the Siliconimist demo.
 *
 * Output is a 1-bit square wave at the note's fundamental frequency, intended
 * to be wired to the TT Audio Pmod (https://github.com/MichaelBell/tt-audio-pmod)
 * on uio[7] per the TT pinouts spec (https://tinytapeout.com/specs/pinouts/).
 * The Pmod's low-pass filter passes audio-band frequencies through directly,
 * so a sub-200kHz "PWM" carrier is fine for chiptune-style buzzer tones.
 *
 * Plays a 4-note arpeggio (C major triad: C4, E4, G4, C5) with each note
 * held for ~60 frame_tick pulses (~1 second at 60 Hz vsync).
 *
 * Half-period divisors are sized for a 25 MHz pixel clock:
 *   half_period = clk_freq / (2 * note_freq)
 *
 *   C4 (261.63 Hz) -> 25_000_000 / 523.26  = 47775 -> 47774 (count to 0)
 *   E4 (329.63 Hz) -> 25_000_000 / 659.26  = 37921 -> 37920
 *   G4 (392.00 Hz) -> 25_000_000 / 784.00  = 31888 -> 31887
 *   C5 (523.25 Hz) -> 25_000_000 / 1046.50 = 23889 -> 23888
 */

`default_nettype none

module chiptune (
    input  wire clk,
    input  wire rst_n,
    input  wire frame_tick,  // one-cycle pulse per VGA frame
    input  wire mute,
    output wire audio
);

  reg  [5:0]  step_counter;   // 0..59 frames per note
  reg  [1:0]  note_index;     // current note in the 4-step loop
  reg  [15:0] tone_counter;   // half-period countdown
  reg         square;

  reg  [15:0] note_div;
  always @(*) begin
    case (note_index)
      2'd0: note_div = 16'd47774;  // C4
      2'd1: note_div = 16'd37920;  // E4
      2'd2: note_div = 16'd31887;  // G4
      2'd3: note_div = 16'd23888;  // C5
    endcase
  end

  always @(posedge clk) begin
    if (~rst_n) begin
      step_counter <= 0;
      note_index   <= 0;
      tone_counter <= 0;
      square       <= 0;
    end else begin
      if (frame_tick) begin
        if (step_counter == 6'd59) begin
          step_counter <= 0;
          note_index   <= note_index + 1'b1;
        end else begin
          step_counter <= step_counter + 1'b1;
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
