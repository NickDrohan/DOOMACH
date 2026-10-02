"""Check a WAV written by `doom wav` against the WAD it came from.

    python harness/wavcheck.py DOOM1.WAD demo.wav

The mixer's arithmetic is simple enough to redo here: a noise the player
makes himself plays at full volume in the centre, which puts each of its
samples s into both sides as trunc(90 * (s - 128) * 256 / 127). So wherever
the pistol fires with nothing else sounding, the file must hold the pistol's
lump, sample for sample. This finds those places and prints what it found:

    frames <n> seconds <s> loud <percent of frames that are not silence>
    peak <largest magnitude> clipped <frames at the limit>
    pistol <times the pistol lump appears exactly> first <seconds>

Exit 0 if the file is sound of the right length with the pistol in it,
1 otherwise.
"""
import struct
import sys
import wave


def lump(wad, name):
    count, directory = struct.unpack_from("<ii", wad, 4)
    for i in range(count - 1, -1, -1):
        offset, size, raw = struct.unpack_from("<ii8s", wad, directory + 16 * i)
        if raw.split(b"\0", 1)[0].decode("ascii").upper() == name:
            return wad[offset:offset + size]
    raise SystemExit("no lump " + name)


def trunc_div(a, b):
    q = abs(a) // b
    return q if a >= 0 else -q


with open(sys.argv[1], "rb") as f:
    wad = f.read()
w = wave.open(sys.argv[2], "rb")
assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (2, 2, 11025), "not 16-bit stereo at 11025"
frames = w.getnframes()
samples = struct.unpack("<%dh" % (frames * 2), w.readframes(frames))
left, right = samples[0::2], samples[1::2]

loud = sum(1 for l, r in zip(left, right) if l or r)
peak = max(max(abs(v) for v in left), max(abs(v) for v in right))
clipped = sum(1 for l, r in zip(left, right) if abs(l) >= 32767 or abs(r) >= 32767)
print("frames %d seconds %.1f loud %.1f%%" % (frames, frames / 11025.0, 100.0 * loud / frames))
print("peak %d clipped %d" % (peak, clipped))

pistol = lump(wad, "DSPISTOL")
body = pistol[8 + 16:len(pistol) - 16]
want = [trunc_div(90 * (s - 128) * 256, 127) for s in bytearray(body[:400])]

# look for the lump's opening, which is distinctive, then confirm the rest
hits = []
first = want[0:8]
i = 0
limit = frames - len(want)
while i < limit:
    if left[i] == first[0] and list(left[i:i + 8]) == first:
        if list(left[i:i + len(want)]) == want and list(right[i:i + len(want)]) == want:
            hits.append(i)
            i += len(want)
            continue
    i += 1
if hits:
    print("pistol %d first %.2f" % (len(hits), hits[0] / 11025.0))
else:
    print("pistol 0")

ok = frames > 11025 and loud > 0 and len(hits) > 0
sys.exit(0 if ok else 1)
