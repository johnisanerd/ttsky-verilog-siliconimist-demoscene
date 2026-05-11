![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Siliconimist Demoscene Entry (TTSKY26a)

A 1x1-tile demoscene entry for the TTSKY26a Tiny Tapeout shuttle by **Siliconimist**.

This is part of a learning project to understand chip design, especially open source chip design, at the Siliconimist!  This is our first tapeout, and third silicon design.  Previously we made one in Wokwi, the second was a very basic counter in Verilog.  And this is our Opus, our great acheivment from standing on the backs of others.  In verilog, it moves the words "SILICONIMIST" around the screen, and plays the Tetris Type A theme.  And we have a logo!

You can see and listen to the demo [here on the VGA Playground](https://vga-playground.com/?repo=https://github.com/johnisanerd/ttsky-verilog-siliconimist-demoscene)!

- VGA output on the [TinyVGA Pmod](https://github.com/mole99/tiny-vga) (`uo[7:0]`): bouncing 128x128 Siliconimist sprite (silicon wafer + "SILICONIMIST" wordmark) on top of cycling 16-pixel rasterbars.
- 1-bit square-wave chiptune playing [Korobeiniki](https://en.wikipedia.org/wiki/Korobeiniki) (Tetris Type A theme) on `uio[7]` for the [TT Audio Pmod](https://github.com/MichaelBell/tt-audio-pmod).

Pinout follows the official [Tiny Tapeout pinouts spec](https://tinytapeout.com/specs/pinouts/) — TinyVGA on the dedicated-output Pmod bank, TT Audio Pmod on the bidirectional Pmod bank.

See [`docs/info.md`](docs/info.md) for some more information about the design and what we did.

## Repository layout

- `src/project.v` — top module `tt_um_siliconimist`, integrates VGA, sprite, rasterbars, chiptune.
- `src/hvsync_generator.v` — standard VGA timing generator (640x480 @ 60 Hz, 25.175 MHz pixel clock).
- `src/palette.v` — 8-entry 6-bit RGB palette.
- `src/bitmap_rom.v` — 128x128 1-bit sprite ROM. Regenerate from artwork via `scripts/gen_logo.py`.
- `src/chiptune.v` — square-wave audio synth.
- `scripts/gen_logo.py` — regenerates `bitmap_rom.v` from a procedurally drawn Siliconimist logo. Outputs `scripts/logo_preview.png` for visual inspection.

## Updating the logo

You can update the logo artwork by running the following command:

```sh
uv run --with pillow python scripts/gen_logo.py
```

This rewrites the `mem[i] = 8'hXX;` block inside `src/bitmap_rom.v` and saves an upscaled preview at `scripts/logo_preview.png`.

The logo artwork is stored in the `scripts/logo_preview.png` file.

## Running the testbench

```sh
cd test
make clean
make -B
```

This drives 3 frames of VGA output through cocotb and saves them as PNGs in `test/output/`. See [`test/README.md`](test/README.md) for more, gives you a preview of what the visual output looks like.

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip. To learn more and get started, visit https://tinytapeout.com.

## What is the Siliconimist?

The Siliconimist is a podcast and blog about the science, economics, and background behind the semiconductor industry.  It is hosted by John Cole, a software engineer and entrepreneur who is passionate about the semiconductor industry.  You can find the podcast [here](https://www.siliconimist.com/).

## What next?

Now we wait.  The shuttle will take a few months, so all we have are hopes, prayers, and the smart engineers at Tiny Tapeout to make it work.  Thoughts and prayers to the team at Tiny Tapeout and Skyworks to make it work.

Let's see if it works.

[![Siliconimist Chip1](./docs/TheSiliconimist.png)](https://siliconimist.com)