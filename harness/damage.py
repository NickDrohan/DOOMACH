"""Write a copy of a WAD with one map reference pointing outside the map.

Sets the first vertex number of a map's first linedef to 65535, which no
shareware map has, so a loader that checks its references must refuse it.
"""
import struct
import sys

src, dst, mapname = sys.argv[1], sys.argv[2], sys.argv[3].upper()
with open(src, "rb") as f:
    wad = bytearray(f.read())
_, count, directory = struct.unpack_from("<4sii", wad, 0)
names = [wad[directory + 16 * i + 8:directory + 16 * i + 16].split(b"\0", 1)[0].decode("ascii")
         for i in range(count)]
linedefs = names.index(mapname) + 2
assert names[linedefs] == "LINEDEFS"
offset = struct.unpack_from("<i", wad, directory + 16 * linedefs)[0]
struct.pack_into("<H", wad, offset, 0xFFFF)
with open(dst, "wb") as f:
    f.write(wad)
