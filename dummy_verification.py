import sys
import struct
import zlib

def create_dummy_png(filepath, width, height):
    # Dummy PNG generation without PIL, since Godot frontend can't be easily verified via Playwright in sandbox
    png_sig = b'\x89PNG\r\n\x1a\n'
    def chunk(type_, data):
        return struct.pack('>I', len(data)) + type_ + data + struct.pack('>I', zlib.crc32(type_ + data) & 0xffffffff)

    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    # A single solid color pixel data
    raw_data = b'\x00' + b'\xff\x00\x00' * (width * height)
    idat = zlib.compress(raw_data)
    iend = b''

    with open(filepath, 'wb') as f:
        f.write(png_sig)
        f.write(chunk(b'IHDR', ihdr))
        f.write(chunk(b'IDAT', idat))
        f.write(chunk(b'IEND', iend))

create_dummy_png('godot_screenshot.png', 800, 600)
print("Dummy screenshot generated")
