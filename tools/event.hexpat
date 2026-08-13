#pragma description FFBE town/exploration <id>_event.bin
#pragma endian big

import std.io;
import std.mem;
import std.string;

// Block bodies can run to tens of KB, past the stock array/pattern caps.
#pragma array_limit 0x400000
#pragma pattern_limit 0x400000

// The word at 0x04 is a format version, and it decides the header size:
// builds before 1023 have one fewer u32 before numTextures. countA..D
// are the "layer and positioning" words -- meaning still unknown; the
// existing parser records them as count_a..count_d for the same reason.
struct Header {
    u32 fileSize            [[color("569CD6")]];
    u32 formatVersion       [[color("D7BA7D")]];
    u32 countA              [[color("404040")]];
    u32 countB              [[color("404040")]];
    u32 countC              [[color("404040")]];
    if (formatVersion >= 1023) {
        u32 countD          [[color("404040")]];
    }
    u32 numTextures         [[color("DCDCAA")]];
};

fn format_texture(ref auto tex) {
    return std::format("0x{:04X}  {}", tex.id, tex.name);
};

// Identical to the map.bin manifest: u16 id, u16 name length, then the
// name.
struct TextureEntry {
    u16 id                  [[color("4EC9B0")]];
    u16 nameLength          [[color("C586C0")]];
    char name[nameLength]   [[color("CE9178")]];
} [[format("format_texture")]];

fn format_block(ref auto b) {
    return std::format("block {}  {}x{} grid  {} entities  {} bytes",
                       b.blockId, b.width, b.height, b.numEntities, b.size);
};

// The body is a run of these, one per numEntities. Reference only: they
// are variable length (56 bytes when type == 1; 39, 54 or much larger for
// type == 0 depending on optional trailing sections) and the length is
// not stored, so they cannot be arrayed.
//
// The header is 25 bytes. rid is 200000 + slot. srcX/srcY are pixels --
// divide by 58 for tile coordinates; only ~2/3 of records sit on an exact
// tile boundary. w/h are the entity's own footprint in pixels and are
// always a multiple of 58, which is the tile size: 58 = 1 tile, 116 = 2,
// 1160 = 20. They are NOT a declaration of the tile size.
struct EntityRecord {
    u32 rid                 [[color("4EC9B0")]];
    u8  type                [[color("D7BA7D")]];
    u32 srcX                [[color("569CD6")]];
    u32 srcY                [[color("569CD6")]];
    u16 w                   [[color("9CDCFE")]];
    u16 h                   [[color("9CDCFE")]];
    s16 collisionOffsetY    [[color("9CDCFE")]];
    u16 interactionHeight   [[color("9CDCFE")]];
    u16 spriteHeight        [[color("9CDCFE")]];
    u16 spriteWidth         [[color("9CDCFE")]];
    // Header ends at 25. The payload opens with the class word (100, 182,
    // 186, 200 ...) followed by 01 01, then the identity slot.
    u16 classWord           [[color("D7BA7D")]];
};

fn format_pstring(ref auto s) { return s.value; };

// Strings anywhere in the body use the same convention as the texture
// manifest: u16 length, then that many ASCII bytes. Place one by hand
// on a length prefix you spot, e.g.  PascalString s @ 0x1C59;
struct PascalString {
    u16 length              [[color("C586C0")]];
    char value[length]      [[color("CE9178")]];
} [[format("format_pstring")]];

// Same framing as a map.bin layer: `size` spans from the start of `size`
// to the start of the next block. The body is width*height tiles at one
// byte each (a collision/passability grid -- only 0x00, 0x01, 0x06, 0x09
// and 0xFF occur), then a u16 entity count, then the records and script.
struct Block {
    u32 size                        [[color("C586C0")]];
    u16 blockId                     [[color("4EC9B0")]];
    u32 width                       [[color("569CD6")]];
    u32 height                      [[color("569CD6")]];
    u8  tiles[width * height]       [[color("264F78")]];
    u16 numEntities                 [[color("DCDCAA")]];
    u8  body[size - 16 - width * height]  [[color("6A9955")]];
} [[format("format_block")]];

struct Event {
    Header header;
    TextureEntry textures[header.numTextures];
    u16 numBlocks           [[color("DCDCAA")]];
    // Bounded positionally; the chain always ends exactly at EOF.
    Block blocks[while($ < std::mem::size())];
};

Event event @ 0x00;
