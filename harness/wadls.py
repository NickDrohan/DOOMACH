"""List a WAD's directory in the format `doom wad` prints.

An independent reading of the file format, so the Mach reader has something
other than itself to agree with.
"""
import struct
import sys


def listing(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, count, directory = struct.unpack_from("<4sii", data, 0)
    lines = ["%s %d" % (magic.decode("ascii"), count)]
    for i in range(count):
        offset, size, raw = struct.unpack_from("<ii8s", data, directory + 16 * i)
        name = raw.split(b"\0", 1)[0].decode("ascii").upper()
        lines.append("%d %s %d %d" % (i, name, offset, size))
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    # bytes, so Windows does not turn each newline into two characters
    sys.stdout.buffer.write(listing(sys.argv[1]).encode("ascii"))
