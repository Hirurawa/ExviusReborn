#pragma description FFBE town/exploration map.bin
#pragma endian big

import std.io;
import std.mem;
import std.string;

// Layer bodies run to ~220 KB, well past the stock array/pattern caps.
#pragma array_limit 0x400000
#pragma pattern_limit 0x400000

// 32-byte file header. The unknown* fields are kept as named members
// rather than padding so ImHex still colors them.
struct Header {
    u32 fileSize        [[color("569CD6")]];
    u32 unknown04       [[color("404040")]];
    u32 initialLayer    [[color("569CD6")]];
    u32 initialX        [[color("569CD6")]];
    u32 initialY        [[color("569CD6")]];
    u32 unknown14       [[color("404040")]];
    u32 unknown18       [[color("404040")]];
    u32 numTextures     [[color("DCDCAA")]];
};

// `ref auto` avoids a forward reference to TextureEntry, which is not
// declared yet at the point the attribute is parsed.
fn format_texture(ref auto tex) {
    return std::format("0x{:04X}  {}", tex.id, tex.name);
};

// u16 atlas id, u16 name length, then that many ASCII bytes.
struct TextureEntry {
    u16 id                  [[color("4EC9B0")]];
    u16 nameLength          [[color("C586C0")]];
    char name[nameLength]   [[color("CE9178")]];
} [[format("format_texture")]];

// NOT this map's layer list. u16 count, then that many u32 values.
// Counts are 0, 14 or 28, and every file with 14 has the exact same set
// (0, 10..14, 20..22, 30..32, 40, 50) while every file with 28 shares a
// different fixed set -- so this is a static table (draw order or layer
// kind, most likely), unrelated to the layers actually present below.
struct LayerKindTable {
    u16 numEntries              [[color("DCDCAA")]];
    u32 entries[numEntries]     [[color("B5CEA8")]];
};

fn format_layer(ref auto layer) {
    return std::format("layer {}  {}x{}  {} bytes",
                       layer.layerId, layer.width, layer.height, layer.size);
};

// 16-byte header, then the body. `size` spans from the start of `size`
// itself to the start of the next layer, so body = size - 16.
struct Layer {
    u32 size                    [[color("C586C0")]];
    u16 layerId                 [[color("4EC9B0")]];
    u16 separator               [[color("404040")]];  // always 1
    u16 assetId                 [[color("D7BA7D")]];
    u16 width                   [[color("569CD6")]];
    u16 height                  [[color("569CD6")]];
    u16 endFlag                 [[color("D7BA7D")]];
    u8  data[size - 16]         [[color("6A9955")]];
} [[format("format_layer")]];

struct Map {
    Header header;
    TextureEntry textures[header.numTextures];
    LayerKindTable layerKinds;
    u16 numLayers               [[color("DCDCAA")]];
    // Bounded positionally rather than by numLayers: the chain always
    // ends exactly at EOF, but 112020300 declares 32 and stores 31.
    Layer layers[while($ < std::mem::size())];
};

Map map @ 0x00;
