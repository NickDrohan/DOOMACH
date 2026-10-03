"""Print the MIDI messages a MUS song produces, as `doom mus` prints them.

    python harness/musdump.py DOOM1.WAD D_E1M1

An independent reading of the MUS format, written from its description
rather than from the Mach player, so the two have to agree by being right.
One line per message: the tick it falls on (140 a second), then the status
byte and the two data bytes in decimal. The song is played once through and
ends with every channel silenced.
"""
import struct
import sys

CONTROLLERS = [0, 0x00, 0x01, 0x07, 0x0A, 0x0B, 0x5B, 0x5D, 0x40, 0x43]
SYSTEM = {10: 0x78, 11: 0x7B, 12: 0x7E, 13: 0x7F, 14: 0x79}


def lump(path, name):
    with open(path, "rb") as f:
        wad = f.read()
    count, directory = struct.unpack_from("<ii", wad, 4)
    for i in range(count - 1, -1, -1):
        offset, size, raw = struct.unpack_from("<ii8s", wad, directory + 16 * i)
        if raw.split(b"\0", 1)[0].decode("ascii").upper() == name.upper():
            return wad[offset:offset + size]
    raise SystemExit("no lump " + name)


def channel(mus):
    if mus == 15:
        return 9
    return mus + 1 if mus >= 9 else mus


def play(data, volume=127):
    scorelen, scorestart = struct.unpack_from("<HH", data, 4)
    end = min(len(data), scorestart + scorelen)
    pos = scorestart
    velocity = [127] * 16
    tick = 0
    out = []

    def byte():
        nonlocal pos
        if pos >= end:
            return 0
        b = data[pos]
        pos += 1
        return b

    while True:
        if pos >= end:
            break
        d = byte()
        kind, mus = (d >> 4) & 7, d & 15
        ch = channel(mus)
        if kind == 0:
            out.append((tick, 0x80 | ch, byte() & 0x7F, 0))
        elif kind == 1:
            note = byte()
            if note & 0x80:
                velocity[mus] = byte() & 0x7F
            out.append((tick, 0x90 | ch, note & 0x7F, velocity[mus]))
        elif kind == 2:
            bend = byte() * 64
            out.append((tick, 0xE0 | ch, bend & 0x7F, (bend >> 7) & 0x7F))
        elif kind == 3:
            sys_event = byte()
            if sys_event in SYSTEM:
                out.append((tick, 0xB0 | ch, SYSTEM[sys_event], 0))
        elif kind == 4:
            number, value = byte(), byte()
            if number == 0:
                out.append((tick, 0xC0 | ch, value & 0x7F, 0))
            elif number < 10:
                if number == 3:
                    value = value * volume // 127
                out.append((tick, 0xB0 | ch, CONTROLLERS[number], value & 0x7F))
        elif kind == 6:
            break
        if d & 0x80:
            delay = 0
            while True:
                b = byte()
                delay = (delay << 7) | (b & 0x7F)
                if not b & 0x80 or pos >= end:
                    break
            tick += delay
    for ch in range(16):
        out.append((tick, 0xB0 | ch, 0x7B, 0))
        out.append((tick, 0xB0 | ch, 0x79, 0))
    return out


if __name__ == "__main__":
    lines = ["%d %d %d %d" % m for m in play(lump(sys.argv[1], sys.argv[2]))]
    sys.stdout.buffer.write(("\n".join(lines) + "\n").encode("ascii"))
