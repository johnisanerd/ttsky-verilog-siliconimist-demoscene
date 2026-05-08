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
- A small square-wave synth (`chiptune.v`) plays the [Korobeiniki](https://en.wikipedia.org/wiki/Korobeiniki) melody (Tetris Type A theme) from the Wikipedia LilyPond transcription. The tune is stored as a 96-entry × 4-bit ROM of eighth-note pitch indices (12 measures of 4/4) and runs at ~150 BPM (12 vsync frames per eighth-note), looping every ~19 s. The 1-bit output drives `uio[7]` directly.

The audio output is a 1-bit square wave at the current note's fundamental frequency (~330–880 Hz across the song's E4–A5 range), not a high-frequency PWM carrier. The TT Audio Pmod's low-pass filter and AC coupling pass these audio-band signals through directly, and the piezo output path on the Pmod has no further filtering. This produces chiptune-style square-wave tones similar to a Game Boy or NES voice channel.

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
