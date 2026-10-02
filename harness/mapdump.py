"""Dump a map in the format `doom map` prints.

An independent reading of the map lumps and of what P_SetupLevel derives from
them, written from the file format and the C source rather than from the Mach
port, so the two have to agree by being right.
"""
import struct
import sys

FRAC = 16
MININT, MAXINT = -2 ** 31, 2 ** 31 - 1
TOP, BOTTOM, LEFT, RIGHT = 0, 1, 2, 3


def wrap(n):
    """Reduce to a signed 32-bit value, as C int arithmetic does."""
    return (n + 2 ** 31) % 2 ** 32 - 2 ** 31


def cdiv(a, b):
    """Integer division truncating toward zero, as C does."""
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def fixed_div(a, b):
    if (abs(a) >> 14) >= abs(b):
        return MININT if (a ^ b) < 0 else MAXINT
    return wrap(cdiv(a << 16, b))


def name(raw):
    return raw.split(b"\0", 1)[0].decode("ascii").upper()


def records(data, fmt):
    size = struct.calcsize(fmt)
    assert len(data) % size == 0
    return [struct.unpack_from(fmt, data, i) for i in range(0, len(data), size)]


def digest(data):
    total = 0
    for byte in bytearray(data):
        total = (total * 31 + byte) & 0xffffffff
    return total


def dump(path, mapname):
    with open(path, "rb") as f:
        wad = f.read()
    _, count, directory = struct.unpack_from("<4sii", wad, 0)
    lumps = [struct.unpack_from("<ii8s", wad, directory + 16 * i) for i in range(count)]
    marker = max(i for i, l in enumerate(lumps) if name(l[2]) == mapname.upper())

    def lump(offset, expected):
        pos, size, raw = lumps[marker + offset]
        assert name(raw) == expected
        return wad[pos:pos + size]

    out = []

    def emit(*fields):
        out.append(" ".join(str(f) for f in fields))

    block = lump(10, "BLOCKMAP")
    orgx, orgy, bw, bh = struct.unpack_from("<4h", block, 0)
    orgx <<= FRAC
    orgy <<= FRAC

    vertexes = [(x << FRAC, y << FRAC) for x, y in records(lump(4, "VERTEXES"), "<2h")]
    emit("vertexes", len(vertexes))
    for i, (x, y) in enumerate(vertexes):
        emit("v", i, x, y)

    sectors = records(lump(8, "SECTORS"), "<2h8s8s3h")
    sides = records(lump(3, "SIDEDEFS"), "<2h8s8s8sH")
    linedefs = records(lump(2, "LINEDEFS"), "<2H3h2h")

    lines = []
    for v1, v2, flags, special, tag, s0, s1 in linedefs:
        (x1, y1), (x2, y2) = vertexes[v1], vertexes[v2]
        dx, dy = x2 - x1, y2 - y1
        if dx == 0:
            slope = 1
        elif dy == 0:
            slope = 0
        else:
            slope = 2 if fixed_div(dy, dx) > 0 else 3
        box = [max(y1, y2), min(y1, y2), min(x1, x2), max(x1, x2)]
        s0 = -1 if s0 == -1 else s0 & 0xffff
        s1 = -1 if s1 == -1 else s1 & 0xffff
        front = sides[s0][5] if s0 != -1 else -1
        back = sides[s1][5] if s1 != -1 else -1
        lines.append((v1, v2, dx, dy, flags, special, tag, s0, s1, slope, box, front, back))

    emit("sectors", len(sectors))
    for i, (floor, ceil, fpic, cpic, light, special, tag) in enumerate(sectors):
        mine = [j for j, l in enumerate(lines) if l[11] == i or l[12] == i]
        box = [MININT, MAXINT, MAXINT, MININT]
        for j in mine:
            for x, y in (vertexes[lines[j][0]], vertexes[lines[j][1]]):
                # M_AddToBox: each axis updates one bound or the other, never both
                if x < box[LEFT]:
                    box[LEFT] = x
                elif x > box[RIGHT]:
                    box[RIGHT] = x
                if y < box[BOTTOM]:
                    box[BOTTOM] = y
                elif y > box[TOP]:
                    box[TOP] = y
        sx = cdiv(wrap(box[RIGHT] + box[LEFT]), 2)
        sy = cdiv(wrap(box[TOP] + box[BOTTOM]), 2)
        radius = 32 << FRAC
        shift = FRAC + 7
        bb = [0, 0, 0, 0]
        bb[TOP] = min(wrap(box[TOP] - orgy + radius) >> shift, bh - 1)
        bb[BOTTOM] = max(wrap(box[BOTTOM] - orgy - radius) >> shift, 0)
        bb[RIGHT] = min(wrap(box[RIGHT] - orgx + radius) >> shift, bw - 1)
        bb[LEFT] = max(wrap(box[LEFT] - orgx - radius) >> shift, 0)
        emit("s", i, floor << FRAC, ceil << FRAC, name(fpic), name(cpic), light, special, tag,
             len(mine), bb[0], bb[1], bb[2], bb[3], sx, sy, ":", *mine)

    emit("sides", len(sides))
    for i, (xoff, yoff, top, bottom, mid, sector) in enumerate(sides):
        emit("d", i, xoff << FRAC, yoff << FRAC, name(top), name(bottom), name(mid), sector)

    emit("lines", len(lines))
    for i, (v1, v2, dx, dy, flags, special, tag, s0, s1, slope, box, front, back) in enumerate(lines):
        emit("l", i, v1, v2, dx, dy, flags, special, tag, s0, s1, slope, *(box + [front, back]))

    segs = []
    for v1, v2, angle, linedef, side, offset in records(lump(5, "SEGS"), "<2HhHHh"):
        line = lines[linedef]
        sidedef = line[7 + side]
        front = sides[sidedef][5]
        other = line[7 + (side ^ 1)]
        back = sides[other][5] if (line[4] & 4) and other != -1 else -1
        segs.append((v1, v2, offset << FRAC, (angle << FRAC) & 0xffffffff, sidedef, linedef, front, back))

    subsectors = records(lump(6, "SSECTORS"), "<2H")
    emit("subsectors", len(subsectors))
    for i, (numsegs, first) in enumerate(subsectors):
        emit("ss", i, segs[first][6], numsegs, first)

    emit("segs", len(segs))
    for i, seg in enumerate(segs):
        emit("g", i, *seg)

    nodes = records(lump(7, "NODES"), "<4h8h2H")
    emit("nodes", len(nodes))
    for i, node in enumerate(nodes):
        emit("n", i, *([c << FRAC for c in node[:12]] + list(node[12:])))

    things = records(lump(1, "THINGS"), "<5h")
    emit("things", len(things))
    for i, thing in enumerate(things):
        emit("t", i, *thing)

    emit("blockmap", orgx, orgy, bw, bh, len(block) // 2, digest(block))
    reject = lump(9, "REJECT")
    emit("reject", len(reject), digest(reject))
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    # bytes, so Windows does not turn each newline into two characters
    sys.stdout.buffer.write(dump(sys.argv[1], sys.argv[2]).encode("ascii"))
