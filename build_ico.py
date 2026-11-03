import struct, zlib, os, math

SRC = r"D:\Program Files\SoundMirror\Flat_vector_app_icon__The_squa_2026-11-03T04-13-45.png"
OUT_DIR = r"D:\Program Files\SoundMirror"
ICO_PATH = os.path.join(OUT_DIR, "app.ico")
PREVIEW_PATH = os.path.join(OUT_DIR, "icon-preview-256.png")

TILE_R = 0.235
BG_HEX = (0x18, 0x5F, 0xA5)


def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    idat = bytearray()
    w = h = bit = ctype = None
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if tag == b"IHDR":
            w, h, bit, ctype, comp, filt, inter = struct.unpack(">IIBBBBB", body)
            assert bit == 8, "only 8-bit supported"
            assert inter == 0, "interlaced not supported"
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
        pos += 12 + ln
    raw = zlib.decompress(bytes(idat))
    nch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    stride = w * nch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if f == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                left = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                b = prev[i]
                c = prev[i - nch] if i >= nch else 0
                pa = abs(b - c)
                pb = abs(a - c)
                pc = abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, nch, out


def to_rgba(w, h, nch, buf):
    rgba = bytearray(w * h * 4)
    if nch == 4:
        rgba[:] = buf
    elif nch == 3:
        for i in range(w * h):
            rgba[i * 4] = buf[i * 3]
            rgba[i * 4 + 1] = buf[i * 3 + 1]
            rgba[i * 4 + 2] = buf[i * 3 + 2]
            rgba[i * 4 + 3] = 255
    elif nch == 1:
        for i in range(w * h):
            v = buf[i]
            rgba[i * 4] = v
            rgba[i * 4 + 1] = v
            rgba[i * 4 + 2] = v
            rgba[i * 4 + 3] = 255
    else:
        for i in range(w * h):
            v = buf[i * 2]
            rgba[i * 4] = v
            rgba[i * 4 + 1] = v
            rgba[i * 4 + 2] = v
            rgba[i * 4 + 3] = buf[i * 2 + 1]
    return rgba


def repair_watermark(w, h, rgba):
    x0 = int(w * 0.80)
    y0 = int(h * 0.92)
    for y in range(y0, h):
        base = y * w * 4
        for x in range(x0, w):
            i = base + x * 4
            rgba[i] = BG_HEX[0]
            rgba[i + 1] = BG_HEX[1]
            rgba[i + 2] = BG_HEX[2]


def apply_round_mask(w, h, rgba, radius_ratio):
    r = radius_ratio * w
    hx = w / 2.0
    hy = h / 2.0
    for y in range(h):
        py = y + 0.5
        dy = abs(py - hy) - (hy - r)
        if dy < 0:
            dy = 0.0
        base = y * w * 4
        for x in range(w):
            px = x + 0.5
            dx = abs(px - hx) - (hx - r)
            if dx < 0:
                dx = 0.0
            d = math.sqrt(dx * dx + dy * dy) - r
            if d <= -0.5:
                a = 1.0
            elif d >= 0.5:
                a = 0.0
            else:
                a = 0.5 - d
            i = base + x * 4
            rgba[i + 3] = int(rgba[i + 3] * a)


def downsample(w, h, rgba, size):
    out = bytearray(size * size * 4)
    for ty in range(size):
        sy0 = (ty * h) // size
        sy1 = max(sy0 + 1, ((ty + 1) * h) // size)
        for tx in range(size):
            sx0 = (tx * w) // size
            sx1 = max(sx0 + 1, ((tx + 1) * w) // size)
            ra = ga = ba = aa = 0
            n = 0
            for sy in range(sy0, sy1):
                row = sy * w * 4
                for sx in range(sx0, sx1):
                    i = row + sx * 4
                    al = rgba[i + 3]
                    ra += rgba[i] * al
                    ga += rgba[i + 1] * al
                    ba += rgba[i + 2] * al
                    aa += al
                    n += 1
            o = (ty * size + tx) * 4
            if aa > 0:
                out[o] = ra // aa
                out[o + 1] = ga // aa
                out[o + 2] = ba // aa
                out[o + 3] = aa // n
            else:
                out[o + 3] = 0
    return out


def png_encode(size, rgba):
    raw = bytearray()
    stride = size * 4
    for y in range(size):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def bmp_entry(size, rgba):
    hdr = struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, size * size * 4, 0, 0, 0, 0)
    rows = []
    stride = size * 4
    for y in range(size - 1, -1, -1):
        row = bytearray()
        off = y * stride
        for x in range(size):
            p = off + x * 4
            row += bytes((rgba[p + 2], rgba[p + 1], rgba[p], rgba[p + 3]))
        rows.append(bytes(row))
    mask_stride = ((size + 31) // 32) * 4
    mask = bytes(mask_stride * size)
    return hdr + b"".join(rows) + mask


def main():
    w, h, nch, buf = read_png(SRC)
    print("源图:", w, "x", h, "通道", nch)
    rgba = to_rgba(w, h, nch, buf)
    repair_watermark(w, h, rgba)
    apply_round_mask(w, h, rgba, TILE_R)

    sizes = [16, 24, 32, 48, 64, 128, 256]
    images = []
    preview = None
    for s in sizes:
        small = downsample(w, h, rgba, s)
        if s == 256:
            preview = png_encode(s, small)
            images.append((s, preview, True))
        else:
            images.append((s, bmp_entry(s, small), False))
        print("  渲染", s, "ok")

    count = len(images)
    header = struct.pack("<HHH", 0, 1, count)
    offset = 6 + 16 * count
    entries = b""
    blobs = b""
    for s, data, is_png in images:
        v = 0 if s >= 256 else s
        entries += struct.pack("<BBBBHHII", v, v, 0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)

    with open(ICO_PATH, "wb") as f:
        f.write(header + entries + blobs)
    with open(PREVIEW_PATH, "wb") as f:
        f.write(preview)
    print("ICO:", ICO_PATH, os.path.getsize(ICO_PATH), "bytes")
    print("PREVIEW:", PREVIEW_PATH)


main()
