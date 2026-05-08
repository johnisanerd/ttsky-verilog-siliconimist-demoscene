"""Generate the Siliconimist sprite bitmap and rewrite src/bitmap_rom.v.

Layout (128x128, 1-bit, black background, white ink):
  - Wafer: 48x48 circle outline with 8 vertical + 8 horizontal grid lines
    clipped to the circle interior, centered horizontally near the top.
  - Wordmark: "SILICONIMIST" in a bold sans, fit to ~120x24, below the wafer.

Pixel packing matches src/bitmap_rom.v:
    addr  = {y[6:0], x[6:3]}
    pixel = mem[addr][x & 7]
i.e. each byte holds 8 horizontal pixels, bit 0 = leftmost, LSB-first.

Outputs:
  - scripts/logo_preview.png  (8x upscaled preview for eyeballing)
  - src/bitmap_rom.v          (the mem[i] = 8'hXX; block is regenerated)

Run with:
    uv run --with pillow python scripts/gen_logo.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

CANVAS: int = 128
WAFER_SIZE: int = 48
WAFER_GRID_LINES: int = 8
WAFER_TOP_Y: int = 8
WORDMARK: str = "SILICONIMIST"
WORDMARK_TARGET_W: int = 120
WORDMARK_TARGET_H: int = 24
WORDMARK_GAP: int = 12

SCRIPT_DIR: Path = Path(__file__).resolve().parent
PROJECT_ROOT: Path = SCRIPT_DIR.parent
ROM_PATH: Path = PROJECT_ROOT / "src" / "bitmap_rom.v"
PREVIEW_PATH: Path = SCRIPT_DIR / "logo_preview.png"

FONT_CANDIDATES: tuple[str, ...] = (
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Black.ttf",
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
)


def _font_path() -> str:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return path
    raise FileNotFoundError(
        "No bold sans-serif TrueType font found in: "
        + ", ".join(FONT_CANDIDATES)
    )


def _fit_font(text: str, max_w: int, max_h: int) -> ImageFont.FreeTypeFont:
    """Return the largest Arial-Bold size whose rendered bbox fits within max_w x max_h."""
    path = _font_path()
    chosen = ImageFont.truetype(path, 8)
    for size in range(8, 64):
        candidate = ImageFont.truetype(path, size)
        bbox = candidate.getbbox(text)
        w = bbox[2] - bbox[0]
        h = bbox[3] - bbox[1]
        if w > max_w or h > max_h:
            break
        chosen = candidate
    return chosen


def build_logo() -> Image.Image:
    """Render the Siliconimist sprite onto a 128x128 1-bit canvas."""
    img = Image.new("1", (CANVAS, CANVAS), 0)
    draw = ImageDraw.Draw(img)

    wafer_left = (CANVAS - WAFER_SIZE) // 2
    wafer_top = WAFER_TOP_Y
    wafer_right = wafer_left + WAFER_SIZE - 1
    wafer_bottom = wafer_top + WAFER_SIZE - 1

    grid = Image.new("1", (CANVAS, CANVAS), 0)
    grid_draw = ImageDraw.Draw(grid)
    step = WAFER_SIZE / WAFER_GRID_LINES
    for i in range(WAFER_GRID_LINES):
        offset = int(round(i * step + step / 2.0))
        gx = wafer_left + offset
        gy = wafer_top + offset
        grid_draw.line([(gx, wafer_top), (gx, wafer_bottom)], fill=1)
        grid_draw.line([(wafer_left, gy), (wafer_right, gy)], fill=1)

    interior = Image.new("1", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(interior).ellipse(
        [wafer_left, wafer_top, wafer_right, wafer_bottom], fill=1
    )
    img.paste(grid, (0, 0), interior)

    draw.ellipse(
        [wafer_left, wafer_top, wafer_right, wafer_bottom],
        outline=1,
        width=2,
    )

    font = _fit_font(WORDMARK, WORDMARK_TARGET_W, WORDMARK_TARGET_H)
    bbox = font.getbbox(WORDMARK)
    text_w = bbox[2] - bbox[0]
    text_x = (CANVAS - text_w) // 2 - bbox[0]
    text_y = wafer_bottom + WORDMARK_GAP - bbox[1]
    draw.text((text_x, text_y), WORDMARK, font=font, fill=1)

    return img


def pack_bits(img: Image.Image) -> list[int]:
    """Pack the 1-bit image to 2048 bytes, LSB-first horizontal.

    Each byte holds 8 horizontal pixels: bit 0 = leftmost, bit 7 = rightmost,
    matching `assign pixel = mem[{y[6:0], x[6:3]}][x & 7];` in bitmap_rom.v.
    """
    if img.size != (CANVAS, CANVAS):
        raise ValueError(f"expected {CANVAS}x{CANVAS} canvas, got {img.size}")
    pixels = img.load()
    out: list[int] = []
    for y in range(CANVAS):
        for byte_x in range(CANVAS // 8):
            byte = 0
            for bit in range(8):
                if pixels[byte_x * 8 + bit, y]:
                    byte |= 1 << bit
            out.append(byte)
    return out


def emit_rom(byte_values: list[int]) -> None:
    """Replace the `initial begin ... end` block inside src/bitmap_rom.v in place."""
    text = ROM_PATH.read_text()
    head, sep_begin, rest = text.partition("initial begin")
    body, sep_end, tail = rest.partition("  end")
    if not sep_begin or not sep_end:
        raise RuntimeError(
            "bitmap_rom.v missing 'initial begin' / '  end' markers; refusing to edit"
        )
    new_body = "\n"
    for i, b in enumerate(byte_values):
        new_body += f"    mem[{i}] = 8'h{b:02x};\n"
    new_body += "  "
    ROM_PATH.write_text(head + sep_begin + new_body + sep_end + tail)


def save_preview(img: Image.Image, scale: int = 8) -> None:
    """Save an upscaled black/white preview PNG for visual inspection."""
    preview = img.convert("L").point(lambda v: 255 if v else 0)
    preview = preview.resize((CANVAS * scale, CANVAS * scale), Image.NEAREST)
    preview.save(PREVIEW_PATH)


def main() -> None:
    img = build_logo()
    save_preview(img)
    byte_values = pack_bits(img)
    emit_rom(byte_values)
    set_pixels = sum(bin(b).count("1") for b in byte_values)
    print(
        f"Wrote {ROM_PATH} ({set_pixels} ink pixels of {CANVAS * CANVAS}). "
        f"Preview at {PREVIEW_PATH}."
    )


if __name__ == "__main__":
    main()
