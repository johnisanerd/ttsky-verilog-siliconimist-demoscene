import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

import os
import glob
import itertools
import struct
import wave
from PIL import Image, ImageChops


@cocotb.test()
async def test_project(dut):

    # Set clock period to 40 ns (25 MHz)
    CLOCK_PERIOD = 40

    # Set VGA timing parameters matching hvsync_generator.v
    H_DISPLAY = 640
    H_FRONT   =  16
    H_SYNC    =  96
    H_BACK    =  48
    V_DISPLAY = 480
    V_FRONT   =  10
    V_SYNC    =   2
    V_BACK    =  33

    # Number of frames to capture
    CAPTURE_FRAMES = 3

    # Derived constants
    H_SYNC_START = H_DISPLAY + H_FRONT
    H_SYNC_END = H_SYNC_START + H_SYNC
    H_TOTAL = H_SYNC_END + H_BACK
    V_SYNC_START = V_DISPLAY + V_FRONT
    V_SYNC_END = V_SYNC_START + V_SYNC
    V_TOTAL = V_SYNC_END + V_BACK

    # Palette mapping uo_out values to RGB color
    # uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]}
    palette = [bytes(3)] * 256
    for r1, r0, g1, g0, b1, b0 in itertools.product(range(2), repeat=6):
        red = 170*r1 + 85*r0
        green = 170*g1 + 85*g0
        blue = 170*b1 + 85*b0
        color_index = b0<<6|g0<<5|r0<<4|b1<<2|g1<<1|r1<<0
        for sync_bits in (0x00, 0x08, 0x80, 0x88):
            palette[color_index | sync_bits] = bytes((red, green, blue))

    # Set up the clock
    clock = Clock(dut.clk, CLOCK_PERIOD, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset the design
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    # Define some functions for capturing lines & frames

    async def check_line(expected_vsync):
        for i in range(H_TOTAL):
            hsync = int(dut.uo_out.value[7])
            vsync = int(dut.uo_out.value[3])
            assert hsync == (0 if H_SYNC_START <= i < H_SYNC_END else 1), "Unexpected hsync pattern"
            assert vsync == expected_vsync, "Unexpected vsync pattern"
            await ClockCycles(dut.clk, 1)

    async def capture_line(framebuffer, offset):
        for i in range(H_TOTAL):
            hsync = int(dut.uo_out.value[7])
            vsync = int(dut.uo_out.value[3])
            assert hsync == (0 if H_SYNC_START <= i < H_SYNC_END else 1), "Unexpected hsync pattern"
            assert vsync == 1, "Unexpected vsync pattern"
            if i < H_DISPLAY:
                framebuffer[offset+3*i:offset+3*i+3] = palette[int(dut.uo_out.value)]
            await ClockCycles(dut.clk, 1)

    async def skip_frame(frame_num):
        dut._log.info(f"Skipping frame {frame_num}")
        await ClockCycles(dut.clk, H_TOTAL*V_TOTAL)

    async def capture_frame(frame_num, check_sync=True):
        framebuffer = bytearray(V_DISPLAY*H_DISPLAY*3)
        for j in range(V_DISPLAY):
            dut._log.info(f"Frame {frame_num}, line {j} (display)")
            line = await capture_line(framebuffer, 3*j*H_DISPLAY)
        if check_sync:
            for j in range(j, j+V_FRONT):
                dut._log.info(f"Frame {frame_num}, line {j} (front porch)")
                await check_line(1)
            for j in range(j, j+V_SYNC):
                dut._log.info(f"Frame {frame_num}, line {j} (sync pulse)")
                await check_line(0)
            for j in range(j, j+V_BACK):
                dut._log.info(f"Frame {frame_num}, line {j} (back porch)")
                await check_line(1)
        else:
            dut._log.info(f"Frame {frame_num}, skipping non-display lines")
            await ClockCycles(dut.clk, H_TOTAL*(V_TOTAL-V_DISPLAY))
        frame = Image.frombytes('RGB', (H_DISPLAY, V_DISPLAY), bytes(framebuffer))
        return frame

    # Start capturing

    os.makedirs("output", exist_ok=True)

    for i in range(CAPTURE_FRAMES):
        frame = await capture_frame(i)
        frame.save(f"output/frame{i}.png")


@cocotb.test()
async def capture_audio(dut):
    """Sample uio_out[7] (audio) at ~98 kHz for 500 ms of sim time and write
    a 16-bit PCM WAV file plus a CSV of the 1-bit raw values. Lets us inspect
    what the chiptune actually produces under the time-division mix."""

    CLOCK_PERIOD_NS = 40           # 25 MHz
    DECIMATION = 256               # sample every 256 clk cycles -> 97.66 kHz
    SIM_MS = 500
    TOTAL_CYCLES = SIM_MS * 1_000_000 // CLOCK_PERIOD_NS
    NUM_SAMPLES = TOTAL_CYCLES // DECIMATION

    clock = Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    os.makedirs("output", exist_ok=True)

    samples = bytearray()                      # 1 byte per sample, 0 or 1
    last_bit = None
    edges = []                                 # cycle indices of each transition
    for i in range(NUM_SAMPLES):
        bit = int(dut.uio_out.value[7])
        samples.append(bit)
        if last_bit is not None and bit != last_bit:
            edges.append(i * DECIMATION)
        last_bit = bit
        await ClockCycles(dut.clk, DECIMATION)

    sample_rate_hz = 1_000_000_000 / (CLOCK_PERIOD_NS * DECIMATION)
    duration_ms = NUM_SAMPLES / sample_rate_hz * 1000

    # Stats
    ones = sum(samples)
    zeros = NUM_SAMPLES - ones
    duty = ones / NUM_SAMPLES if NUM_SAMPLES else 0.0
    edges_per_sec = len(edges) / (duration_ms / 1000) if duration_ms else 0.0

    dut._log.info(
        "AUDIO: %d samples @ %.1f kHz over %.1f ms; duty=%.1f%% ones=%d zeros=%d "
        "transitions=%d (%.0f/s)",
        NUM_SAMPLES, sample_rate_hz / 1000, duration_ms, duty * 100,
        ones, zeros, len(edges), edges_per_sec,
    )

    # Per-frame duty cycle to spot envelope shape (1 frame = 16.67 ms ~= 1628 samples)
    samples_per_frame = int(sample_rate_hz / 60)
    frame_lines = []
    for f in range(min(20, NUM_SAMPLES // samples_per_frame)):
        chunk = samples[f * samples_per_frame:(f + 1) * samples_per_frame]
        d = sum(chunk) / len(chunk) if chunk else 0
        frame_lines.append(f"  frame {f:2d}: duty={d * 100:5.1f}%  ones={sum(chunk):4d}/{len(chunk)}")
    dut._log.info("AUDIO per-frame duty:\n" + "\n".join(frame_lines))

    # 16-bit PCM WAV: scale 0/1 to -16384/+16384
    pcm = bytearray()
    for b in samples:
        v = 16384 if b else -16384
        pcm += struct.pack("<h", v)
    with wave.open("output/audio.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(int(sample_rate_hz))
        w.writeframes(bytes(pcm))

    # Edge intervals -> dominant audio period(s)
    if len(edges) >= 2:
        deltas = [edges[i + 1] - edges[i] for i in range(len(edges) - 1)]
        # 25 MHz clock; convert clk-cycle delta to Hz
        freqs_hz = [25_000_000 / (2 * d) for d in deltas if d > 0]
        if freqs_hz:
            avg = sum(freqs_hz) / len(freqs_hz)
            dut._log.info(
                "AUDIO: %d edges, avg implied half-period freq=%.0f Hz "
                "(min=%.0f max=%.0f)",
                len(edges), avg, min(freqs_hz), max(freqs_hz),
            )

    # Dump CSV of (cycle_index, bit) for first 20k samples for offline analysis
    with open("output/audio.csv", "w") as f:
        f.write("sample_index,clk_cycle,bit\n")
        for i, b in enumerate(samples[:20000]):
            f.write(f"{i},{i * DECIMATION},{b}\n")


@cocotb.test()
async def compare_reference(dut):

    if not os.path.isdir("reference"):
        dut._log.info("No reference/ directory; skipping reference comparison")
        return

    for img in glob.glob("output/frame*.png"):
        basename = img.removeprefix("output/")
        dut._log.info(f"Comparing {basename} to reference image")
        frame = Image.open(img)
        ref = Image.open(f"reference/{basename}")
        diff = ImageChops.difference(frame, ref)
        if diff.getbbox() is not None:
            diff.save(f"output/diff_{basename}")
            assert False, f"Rendered {basename} differs from reference image"
