"""Recover a transparent still from two photographs of the same frame.

    python3 -I scripts/mascot_still_matte.py <over-black.bmp> <over-white.bmp> <out.png> \
        --crop X Y W H

Over black a pixel is a*C; over white it is a*C + (1 - a). So
a = 1 - (white - black) and C = black / a. Stdlib only; the inputs are
24- or 32-bit BMPs (`sips -s format bmp`).
"""

import argparse
import struct
import zlib


def read_bmp(path):
    data = open(path, "rb").read()
    offset = struct.unpack_from("<I", data, 10)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    if bpp not in (24, 32):
        raise SystemExit(f"{path}: {bpp}-bit BMP not supported")
    step = bpp // 8
    stride = (width * step + 3) & ~3
    flipped = height > 0
    height = abs(height)

    def pixel(x, y):
        row = height - 1 - y if flipped else y
        i = offset + row * stride + x * step
        b, g, r = data[i], data[i + 1], data[i + 2]
        return r, g, b

    return width, height, pixel


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(kind, body):
        return (struct.pack(">I", len(body)) + kind + body
                + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    open(path, "wb").write(png)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("black")
    parser.add_argument("white")
    parser.add_argument("out")
    parser.add_argument("--crop", type=int, nargs=4, required=True, metavar=("X", "Y", "W", "H"))
    args = parser.parse_args()
    wb, hb, black = read_bmp(args.black)
    ww, hw, white = read_bmp(args.white)
    if (wb, hb) != (ww, hw):
        raise SystemExit("the two photographs differ in size")
    x0, y0, w, h = args.crop
    if x0 < 0 or y0 < 0 or x0 + w > wb or y0 + h > hb:
        raise SystemExit("crop falls outside the photographs")
    rows = []
    for y in range(y0, y0 + h):
        row = []
        for x in range(x0, x0 + w):
            kb = black(x, y)
            kw = white(x, y)
            spread = sum(cw - cb for cb, cw in zip(kb, kw)) / 3
            a = max(0.0, min(1.0, 1 - spread / 255))
            if a < 1 / 255:
                row += [0, 0, 0, 0]
                continue
            row += [min(255, round(c / a)) for c in kb] + [round(a * 255)]
        rows.append(row)
    write_png(args.out, w, h, rows)


if __name__ == "__main__":
    main()
