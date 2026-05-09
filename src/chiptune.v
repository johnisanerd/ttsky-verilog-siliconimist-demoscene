/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tiny chiptune square-wave synth for the Siliconimist demo.
 *
 * Plays "Korobeiniki" (the Tetris Type A theme) as a 1-bit square wave.
 * Includes combinational ROM optimization and explicit rest articulation.
 */

`default_nettype none

module chiptune (
    input  wire clk,         // Main system clock (25.175 MHz for VGA)
    input  wire rst_n,       // Active-low reset signal
    input  wire frame_tick,  // A one-clock-cycle pulse that fires exactly once per VGA frame (~60 Hz)
    input  wire mute,        // External signal to completely silence the output
    output wire audio        // 1-bit square wave output sent to the TT Audio Pmod
);

  // --- TIMING CONSTANTS ---
  // The VGA frame_tick fires at 60 Hz. We wait 12 frames to advance to the next eighth-note.
  // 60 frames / 12 = 5 steps per second.
  // 5 steps per second * 60 seconds = 300 eighth-notes per minute.
  // Since a quarter note is two eighth-notes, this equals 150 BPM.
  localparam FRAMES_PER_STEP = 12;  
  
  // The total length of the song loop in eighth-note steps (12 measures * 8 eighths = 96 steps)
  localparam SONG_LEN        = 96;  

  // --- STATE REGISTERS ---
  // These registers keep track of where we are in the song and in time.
  reg [3:0] frame_in_step;          // Counts from 0 to 11 to track frames until the next note step
  reg [6:0] song_step;              // Counts from 0 to 95 to track the current eighth-note in the song

  // --- SONG ROM (Read-Only Memory) ---
  // cur_pitch holds a 4-bit index that represents the current musical note (or a rest).
  reg [3:0] cur_pitch;

  // This `always @(*)` block with a `case` statement explicitly tells the synthesis tool 
  // to build a "Combinational ROM" (a lookup table of logic gates, not flip-flops).
  // Based on the current `song_step`, it outputs the correct 4-bit pitch index.
  // We use `4'd15` (decimal 15) to represent a "rest" (silence).
  always @(*) begin
    case (song_step)
      // m1: E4(dq) G#4(e) B4(q) G#4(e) E4(e)
      // (dq = dotted quarter = 3 eighth notes, e = 1 eighth note, q = 2 eighth notes)
      7'd0, 7'd1, 7'd2:          cur_pitch = 4'd0;  // E4 held for 3 steps
      7'd3:                      cur_pitch = 4'd1;  // G#4 for 1 step
      7'd4, 7'd5:                cur_pitch = 4'd3;  // B4 held for 2 steps
      7'd6:                      cur_pitch = 4'd1;  // G#4 for 1 step
      7'd7:                      cur_pitch = 4'd0;  // E4 for 1 step
      
      // m2: A4(dq) C5(e) E5(q) D5(e) C5(e)
      7'd8, 7'd9, 7'd10:         cur_pitch = 4'd2;
      7'd11:                     cur_pitch = 4'd4;
      7'd12, 7'd13:              cur_pitch = 4'd6;
      7'd14:                     cur_pitch = 4'd5;
      7'd15:                     cur_pitch = 4'd4;
      
      // m3: B4(dq) C5(e) D5(q) E5(q)
      7'd16, 7'd17, 7'd18:       cur_pitch = 4'd3;
      7'd19:                     cur_pitch = 4'd4;
      7'd20, 7'd21:              cur_pitch = 4'd5;
      7'd22, 7'd23:              cur_pitch = 4'd6;
      
      // m4: C5(q) A4(q) [REST] A4(h)
      // Notice the rest (15) inserted here to provide separation between the two A4 notes!
      7'd24, 7'd25:              cur_pitch = 4'd4;
      7'd26:                     cur_pitch = 4'd2; 
      7'd27:                     cur_pitch = 4'd15; // REST (silence for articulation)
      7'd28, 7'd29, 7'd30, 7'd31:cur_pitch = 4'd2;
      
      // m5 & m9: F5(dq) G5(e) A5(q) G5(e) F5(e)
      // Since measures 5-8 are identical to measures 9-12, we can reuse the logic
      // by including both step numbers (e.g., 32 and 64) for the same note.
      7'd32, 7'd33, 7'd34, 7'd64, 7'd65, 7'd66: cur_pitch = 4'd7;
      7'd35, 7'd67:                             cur_pitch = 4'd8;
      7'd36, 7'd37, 7'd68, 7'd69:               cur_pitch = 4'd9;
      7'd38, 7'd70:                             cur_pitch = 4'd8;
      7'd39, 7'd71:                             cur_pitch = 4'd7;
      
      // m6 & m10: E5(dq) F5(e) E5(q) D5(e) C5(e)
      7'd40, 7'd41, 7'd42, 7'd72, 7'd73, 7'd74: cur_pitch = 4'd6;
      7'd43, 7'd75:                             cur_pitch = 4'd7;
      7'd44, 7'd45, 7'd76, 7'd77:               cur_pitch = 4'd6;
      7'd46, 7'd78:                             cur_pitch = 4'd5;
      7'd47, 7'd79:                             cur_pitch = 4'd4;
      
      // m7 & m11: B4(dq) C5(e) D5(q) E5(q)
      7'd48, 7'd49, 7'd50, 7'd80, 7'd81, 7'd82: cur_pitch = 4'd3;
      7'd51, 7'd83:                             cur_pitch = 4'd4;
      7'd52, 7'd53, 7'd84, 7'd85:               cur_pitch = 4'd5;
      7'd54, 7'd55, 7'd86, 7'd87:               cur_pitch = 4'd6;
      
      // m8 & m12: C5(q) A4(q) [REST] A4(h)
      7'd56, 7'd57, 7'd88, 7'd89:               cur_pitch = 4'd4;
      7'd58, 7'd90:                             cur_pitch = 4'd2;
      7'd59, 7'd91:                             cur_pitch = 4'd15; // REST
      7'd60, 7'd61, 7'd62, 7'd63, 7'd92, 7'd93, 7'd94, 7'd95: cur_pitch = 4'd2;
      
      // Default case acts as a safety net. If song_step goes out of bounds, play a rest.
      default: cur_pitch = 4'd15;
    endcase
  end

  // --- FREQUENCY DIVIDER ROM ---
  // This takes the pitch index (0 to 9) and outputs the "half-period divisor".
  // A square wave toggles HIGH and LOW. The divisor tells us how many 25.175 MHz clock cycles
  // to wait before toggling the state, which generates the desired frequency.
  // Formula: note_div = floor(clk_freq / (2 * note_freq)) - 1
  reg [15:0] note_div;
  always @(*) begin
    case (cur_pitch)
      4'd0:    note_div = 16'd38184; // E4   (329.63 Hz)
      4'd1:    note_div = 16'd30307; // G#4  (415.30 Hz)
      4'd2:    note_div = 16'd28607; // A4   (440.00 Hz)
      4'd3:    note_div = 16'd25485; // B4   (493.88 Hz)
      4'd4:    note_div = 16'd24055; // C5   (523.25 Hz)
      4'd5:    note_div = 16'd21433; // D5   (587.33 Hz)
      4'd6:    note_div = 16'd19091; // E5   (659.26 Hz)
      4'd7:    note_div = 16'd18020; // F5   (698.46 Hz)
      4'd8:    note_div = 16'd16054; // G5   (783.99 Hz)
      4'd9:    note_div = 16'd14303; // A5   (880.00 Hz)
      default: note_div = 16'd0;     // Rest (0 means don't count)
    endcase
  end

  // --- AUDIO SYNTHESIS LOGIC ---
  // tone_counter: counts down from note_div to 0.
  // square: the actual 1-bit waveform state (0 or 1) that flips every time the counter hits 0.
  reg [15:0] tone_counter;
  reg        square;

  // This block runs every single cycle of the 25.175 MHz clock.
  always @(posedge clk) begin
    // Synchronous active-low reset: If rst_n is 0, reset all counters to their default state.
    if (~rst_n) begin
      frame_in_step <= 0;
      song_step     <= 0;
      tone_counter  <= 0;
      square        <= 0;
    end else begin
      
      // 1. Timing advancement (Macro-timing)
      // When the VGA circuitry signals a new frame has begun...
      if (frame_tick) begin
        // If we have hit our target frames per note...
        if (frame_in_step == FRAMES_PER_STEP - 1) begin
          frame_in_step <= 0; // Reset frame counter
          // Advance song step, or loop back to 0 if we reached the end of the song
          song_step <= (song_step == SONG_LEN - 1) ? 0 : song_step + 1'b1;
        end else begin
          frame_in_step <= frame_in_step + 1'b1; // Otherwise, just count the frame
        end
      end

      // 2. Tone generation (Micro-timing)
      // SPECIAL CASE: Prevent audio glitches.
      // At the exact moment a new note step begins (the last frame tick of the current note),
      // we must reset the tone_counter to 0. This guarantees the new note starts fresh,
      // instead of accidentally continuing to count down from the previous note's divisor.
      if (frame_tick && frame_in_step == FRAMES_PER_STEP - 1) begin
        tone_counter <= 0;
        square <= 0;
      end else begin
        // STANDARD CASE: Generating the square wave.
        if (tone_counter == 0) begin
          // The counter hit 0! Load the new divisor and flip the square wave state.
          tone_counter <= note_div;
          square       <= ~square;
        end else begin
          // Not zero yet, keep counting down.
          tone_counter <= tone_counter - 1'b1;
        end
      end
      
    end
  end

  // --- OUTPUT MULTIPLEXER ---
  // Determine if we should be playing a rest.
  wire is_rest = (cur_pitch == 4'd15);
  
  // Assign the final audio output. 
  // If the mute switch is ON, OR if we are playing a rest, force the output to 0 (silence).
  // Otherwise, output the generated square wave.
  assign audio = (mute | is_rest) ? 1'b0 : square;

endmodule