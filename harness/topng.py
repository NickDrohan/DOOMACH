"""Convert a PPM frame from `doom frame` to a PNG, optionally enlarged.

    python harness/topng.py frame.ppm frame.png [scale]

Needs Pillow. Enlarging repeats pixels, so the picture stays exactly what the
renderer drew.
"""
import sys

from PIL import Image

image = Image.open(sys.argv[1])
scale = int(sys.argv[3]) if len(sys.argv) > 3 else 1
if scale > 1:
    image = image.resize((image.width * scale, image.height * scale), Image.NEAREST)
image.save(sys.argv[2])
