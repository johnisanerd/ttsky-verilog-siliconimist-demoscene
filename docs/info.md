<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The Siliconimist demo is a 1x1-tile demoscene entry built on the VGA Playground "Logo" preset. It drives a 640x480 @ 60 Hz signal on the TinyVGA Pmod and a 1-bit square-wave chiptune on the TT Audio Pmod.

- A 128x128 bitmap ROM holds a 1-bit Siliconimist sprite: a silicon wafer (circle with an 8x8 grid of die outlines) above a bold "SILICONIMIST" wordmark.
- The sprite bounces around the screen, ricocheting off all four edges. Each bounce advances a 3-bit color index that recolors the sprite ink from an 8-entry palette.
- Behind the sprite, 16-pixel-tall rasterbars cycle vertically once per frame, picking colors from the same palette indexed by `pix_y[6:4] + frame_counter[5:3]`.
- A four-voice chiptune (`chiptune.v`) plays the [Korobeiniki](https://en.wikipedia.org/wiki/Korobeiniki) melody (Tetris Type A theme), stored as a 96-entry × 4-bit ROM of eighth-note pitch indices and running at ~112 BPM (16 vsync frames per eighth-note), looping every ~25.6 s. Architecture is adapted from [rejunity's Drop demo](https://github.com/rejunity/tt08-vga-drop): oscillator counters tick at the VGA scanline rate (~31.5 kHz), and the four voices (kick, snare, lead, bass) are mixed by **time-division across the scanline** — each voice owns a fixed x-window and the audio output is `OR(voices)`. Note envelopes come from `~timer[N:0]` shaping the voice's window width, so envelope = 0 means zero-wide window means voice silent. Snare uses a 13-bit LFSR gated to the backbeat; kick is a 60 Hz pulse train derived from `pix_y < 262`. The 1-bit mixed output drives `uio[7]` directly; the TT Audio Pmod's low-pass filter integrates the time-multiplexed voices into perceived polyphony.

## How to test

1. Plug a TinyVGA Pmod ([mole99/tiny-vga](https://github.com/mole99/tiny-vga)) into the dedicated-output Pmod bank and connect a VGA monitor.
2. Plug a TT Audio Pmod ([MichaelBell/tt-audio-pmod](https://github.com/MichaelBell/tt-audio-pmod)) into the bidirectional Pmod bank — its input is on `uio[7]`.
3. Pulse `rst_n` low briefly. The Siliconimist sprite should appear bouncing on a moving rasterbar background; the Pmod should play Korobeiniki (Tetris theme) on a loop.
4. Toggle `ui[1]` to enable per-bounce color cycling (otherwise the sprite is white).
5. Toggle `ui[0]` to tile the sprite full-screen (handy for confirming the bitmap data).
6. Hold `ui[2]` high to mute the audio output.

## External hardware

The pinout follows the official [Tiny Tapeout pinouts spec](https://tinytapeout.com/specs/pinouts/):

- **VGA**: TinyVGA Pmod on the dedicated output bank `uo[7:0]` ([mole99/tiny-vga](https://github.com/mole99/tiny-vga)).
- **Audio**: TT Audio Pmod with mono input on `uio[7]` ([MichaelBell/tt-audio-pmod](https://github.com/MichaelBell/tt-audio-pmod)). The lower bidirectional pins `uio[6:0]` are tied low / disabled, leaving the Pmod's pass-through row free for compatibility.
