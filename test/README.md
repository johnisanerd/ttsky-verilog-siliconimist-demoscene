# Sample testbench for The Siliconimist Demoscene Entry

This is a testbench for the [Siliconimist Demoscene Entry](https://siliconimist.com) for the TTSKY26a Tiny Tapeout shuttle. It uses [cocotb](https://docs.cocotb.org/en/stable/) to drive the DUT and check the outputs.

This is a sample testbench for a Tiny Tapeout project. It uses [cocotb](https://docs.cocotb.org/en/stable/) to drive the DUT and check the outputs.
See below to get started or for more information, check the [website](https://tinytapeout.com/hdl/testing/).
The VGA testing code is adapted from Tiny Tapeout's [VGA Playground](https://vga-playground.com/?preset=logo) project, and you can watch and listen to the music of my people [here on the playground here](https://vga-playground.com/?repo=https://github.com/johnisanerd/ttsky-verilog-siliconimist-demoscene).

## Setting up

1. Edit [Makefile](Makefile) and modify `PROJECT_SOURCES` to point to your Verilog files.
2. Edit [tb.v](tb.v) and replace `tt_um_vga_example` with your module name.

## How to run

To run the RTL simulation:

```sh
make clean
make -B
```

This drives 3 frames of VGA output through cocotb and saves them as PNGs in `test/output/`.  They show up as PNG's.  

## Audio capture (`output/audio.wav`)

`test.capture_audio` samples `uio_out[7]` and writes `output/audio.wav` (~97.656 kHz mono). Simulation length defaults to **4 seconds**:

```sh
make -B AUDIO_SIM_MS=3500    # ~3.5 s WAV
make -B AUDIO_SIM_MS=500     # quicker capture for iteration
```

## How to view the waveform file

Actually, this should work in theory, but as of 2026-05-11 it doesn't, I still don't understand what I'm looking at here.  

Using Surfer:

```sh
surfer tb.fst
```


## Follow Along and Watch the Drama Unfold

