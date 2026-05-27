# MapBuilder — FFBE `.bin` Map Format Recipe

This document captures everything we've reverse-engineered about the
FFBE map / cutscene `.bin` formats and the surrounding pipelines (Python
parsers → JSON blueprints → Godot scenes). Use it as a recipe both for
parsing new bins and for understanding how the runtime consumes the
output.

Two distinct binary families are handled:

* **Map bins** (`town_data/<town_id>/map.bin`) — the static field maps
  every town and dungeon is built from. Two on-disk variants are now
  decoded:
  - `town_v1` — the original chunked layout (towns, simple dungeons).
  - `exploration_v2` — a layer-table layout used by exploration zones.
* **Event bins** (`memorial-assets/.../<event_id>/<event_id>_event.bin`)
  — cutscene / story scripts that play *on top of* a map. Header +
  asset manifest + a variable-length opcode stream.

All multi-byte integers in either family are **big-endian** unless
noted.

---

## 1. Asset layout

### 1.1 Maps

Each town/dungeon is a self-contained folder. The Godot runtime expects
the following structure under `{town_data_root}/{town_id}/`:

```
{town_id}/
    map.bin                    -- raw FFBE binary (input to parse.py)
    map_blueprint.json         -- parser output, consumed by tile_map.gd
    mapchip_xxxx_yyy.png       -- atlas textures referenced by map.bin's manifest
    mapchip_xxxx_yyy.png.import
    ...
```

Switch maps at runtime via `tile_map.load_town("1102")`. The TileMap's
`town_data_root` export (default `res://assets/town_data`) is the
prefix. Short ids (`1102`) are resolved against
`town_data/towns.json` and `town_data/dungeons.json`
(`bin_common.resolve_town_folder_id`); full folder ids (`111020300`) are
used as-is.

### 1.2 Events

Cutscene scripts live under the on-demand asset pack root
(`event_common.EVENT_ASSET_ROOT`), one folder per event id:

```
assets/memorial-assets/assetpacks/on_demand_asset4/199/199/assets/
    <event_id>/
        <event_id>_event.bin        -- raw FFBE cutscene script
        <event_id>_event_text.txt   -- "<text_id>,<line>" CSV side-car
                                       (loaded by both the parser and
                                       the runtime for dialog preview)
        event_blueprint.json        -- event_parser.py output
```

The event id encodes its parent map id: an event
`XXXXXXXY1`, `XXXXXXXY2`, … runs on map `XXXXXXXY0` (e.g. event
`111020301` runs on map `111020300`). `event_runner.gd` uses this
convention to ask the sibling TileMap to load the underlying map
before running the script.

---

## 2. High-level pipelines

### 2.1 Maps

```
┌──────────────┐     parse.py         ┌────────────────────┐    tile_map.gd     ┌──────────────┐
│  map.bin     │  ──────────────────▶ │ map_blueprint.json │  ─────────────────▶│ Godot scene   │
│ (FFBE input) │  (dispatcher; calls  │ (machine readable) │  cached + rendered │ + collision   │
└──────────────┘   town_parser OR     └────────────────────┘                    └──────────────┘
                   exploration_parser
                   based on the
                   variant sniff)
```

- `parse.py` is a thin dispatcher: it reads the shared file header
  (`bin_common.read_common_prefix`) and delegates to
  `town_parser.parse_ffbe_map` or
  `exploration_parser.parse_exploration_map` based on the variant byte
  pattern (see §3.1).
- `tile_map.gd` reads `map.bin` at runtime *only* to rebuild the
  TileSet (`build_dynamic_tileset()` uses the manifest's atlas
  filenames). All other rendering comes from the JSON blueprint.

### 2.2 Events

```
┌────────────────────┐  event_parser.py   ┌─────────────────────┐  event_runner.gd ┌──────────────┐
│ <id>_event.bin     │ ──────────────────▶│ event_blueprint.json│ ────────────────▶│ Event.tscn   │
│ <id>_event_text.txt│  walks header +    │ + opcode stream     │  drives TileMap, │ playback     │
└────────────────────┘  manifest + ops    └─────────────────────┘  Camera2D,       └──────────────┘
                                                                  EventActors
```

- `event_parser.py` decodes the 28-byte event header, the asset
  manifest, and the opcode stream into JSON. See §9.
- `event_runner.gd` (attached to the `Event.tscn` root) loads the
  blueprint, asks the sibling TileMap to load the matching map, spawns
  one `EventActor` per `actor_id`, and walks the opcode list.

---

## 3. `map.bin` structure

### 3.1 File-level header (32 bytes) + texture manifest

Both `town_v1` and `exploration_v2` share the same 32-byte file header
and texture manifest layout. The header is structured (no `"mapchip"`
string search needed — the texture filenames inside the manifest just
*happen* to start with `mapchip_`):

```
offset 0x00  u32 file_size           -- byte length, matches os.stat
offset 0x04  u32 metadata_a          -- unknown
offset 0x08  u32 initial_layer_id    -- chunk lid the engine loads first
offset 0x0C  u32 initial_player_x    -- spawn tile X on initial_layer_id
offset 0x10  u32 initial_player_y    -- spawn tile Y
offset 0x14  u32 metadata_b          -- unknown
offset 0x18  u32 metadata_c          -- unknown
offset 0x1C  u32 num_textures        -- texture-manifest entry count
offset 0x20  texture manifest:
    repeat num_textures times:
        u16 atlas_id           -- canonical FFBE atlas id (10000-20039)
        u16 str_len            -- byte length of the filename that follows
        char[str_len] filename -- ASCII basename, e.g. "mapchip_0010_001.png"
```

Each declared atlas is mapped to a sequential Godot `source_id`
(0, 1, 2, …) in the same order it appears in the manifest. The pair
`(atlas_id → godot source_id)` becomes `tile_map.id_map`.

`event_runner.gd` and the layer-resolver consult `initial_layer_id` /
`initial_player_x` / `initial_player_y` when deciding which layer to
show for a per-event scene that doesn't explicitly carry one.

### 3.1.1 Variant sniff

The 4 bytes *after* the texture manifest decide which body parser runs
(`bin_common.detect_variant`):

* If `peek[0] == 0 and peek[1] == 0` → `town_v1` (the next u32 is
  `total_chunks`; no real map has ≥ 65 536 chunks, so the upper two
  bytes are always zero).
* Otherwise → `exploration_v2` (the next u16 is `layer_count` and is
  non-zero, so its high byte never matches the v1 pattern).

This README documents the `town_v1` body. `exploration_v2` lives in
`exploration_parser.py` (header-compatible, then a fixed 14-slot
layer table followed by per-layer blocks).

### 3.2 Chunks (= layers / rooms)

After the manifest:

```
    u32 total_chunks
    repeat total_chunks times:
        chunk-header + chunk-body  (chunk_size bytes total, including header)
```

#### 3.2.1 Chunk header (16 bytes)

```
    u32 chunk_size          -- absolute byte length of this chunk including
                               this 16-byte header
    u16 layer_id            -- canonical "lid" used by warps
    u16 sep1                -- always 0 in this corpus
    u16 asset_id            -- internal, not used at runtime
    u16 grid_width          -- in tiles (tile = 58 px)
    u16 grid_height
    u16 end_flag            -- always 0
```

The chunk body is then:

```
    [visual layers]            -- N layers, each grid_width*grid_height*4 bytes
    [inter-visual separators]  -- 0..3 \x00 pad bytes + optional \x01
    [collision layer]          -- grid_width*grid_height*1 byte
    [region layer]             -- grid_width*grid_height*1 byte
    [objects section]          -- variable, see §3.3
```

The visual-layer count is **not stored explicitly** — the parser
derives it from the chunk's remaining space:

```
available = chunk_size - 16 - 2 * (grid_w * grid_h)
visual_count = floor(available / (grid_w * grid_h * 4))
```

Between visual layers there is an inter-section gap of `0..3 \x00`
bytes optionally followed by a single `\x01` separator. The gap may be
zero bytes (chunk 26 / lid 110 is the canonical example where two
visual layers abut directly). `consume_separator()` in the parser
implements the lenient byte-vacuum required to align all observed
chunks. A handful of chunks (lids 127/128) also place this gap *before*
the first visual layer.

#### 3.2.2 Visual layer cell encoding (4 bytes per tile)

```
    u16 atlas_id        -- 0xFFFF means transparent/empty
    u16 sprite_idx      -- linear index into the atlas's 17-wide tile grid:
                              atlas_x = sprite_idx % 17
                              atlas_y = sprite_idx / 17
```

`atlas_id == 10000` is the special "empty grass" placeholder used
extensively as a transparent fill. Atlas grid width = 17 (constant
across the corpus).

#### 3.2.3 Collision layer (1 byte per tile)

`0` = walkable, non-zero = blocking. Rendered at runtime by
`_draw_collision_overlay()` as a debug overlay and by
`debug_cells_collision` → `physics_container` (StaticBody2D with one
RectangleShape2D per blocking cell).

#### 3.2.4 Region layer (1 byte per tile)

Region/zone ids used by gameplay scripts. Not interpreted by the
TileMap; recorded in the blueprint for completeness.

### 3.3 Objects section (after region layer)

Four back-to-back sub-sections, in this order:

```
    u32 ge_count   + ge_count   * 9 B  grid_event records
    u16 ge_trailer (always 0x0000)
    u32 sa_count   + sa_count   * 27 B static_asset records
    u16 de_count   + variable-length   dynamic_entity records
```

#### 3.3.1 Grid events (9 B each)

```
    u32 x            -- tile coord
    u32 y            -- tile coord
    u8  event_id
```

| event_id | meaning                  | constraint applied by player.gd      |
|----------|--------------------------|--------------------------------------|
| 1        | stair, top-left → bottom-right (↘) | force diagonal motion along (1, 1) |
| 2        | stair, bottom-left → top-right (↗) | force diagonal motion along (1,-1) |
| 3        | ladder body              | force vertical motion (axis-locked) |
| 4        | ladder anchor (top/bot)  | force vertical motion (axis-locked) |

#### 3.3.2 Static assets (27 B each)

The decorative/over-floor sprite layer. Each record is a blit
rectangle from an external atlas into pixel-space on the chunk.

```
    u32 map_x_px        -- destination on the map
    u32 map_y_px
    u16 width_px        -- usually multiple of 58
    u16 height_px
    u16 render_flag     -- always 1 in this corpus
    u16 atlas_id        -- foreign key into manifest atlas ids
    u16 atlas_x_px      -- source X inside that atlas (99.8% multiples of 58)
    u16 atlas_y_px      -- source Y                   (99.9% multiples of 29)
    u16 flags_a         -- observed: 0, 259, 260
    u16 variant_word    -- packed: low byte = visual sub-layer (0..3)
                                   high byte = layer_flags (0, 10, 12, 15)
    u16 flags_c         -- observed: 0, 256
    u8  scale_pct       -- 100 = 1.0x. Observed: 50, 70, 80, 85, 90, 100, 150, 200
```

**Common pitfall:** the field at offset 16 is an **atlas pixel
X-coordinate**, not an opaque "sprite id". An earlier version of the
renderer mis-read it as an id and produced totally unrelated tiles on
the map. The `(atlas_id, atlas_x_px, atlas_y_px, width_px, height_px)`
tuple is what selects the source rectangle.

#### 3.3.3 Dynamic entities (variable length, 25-byte common header)

```
    u32 record_id            -- 1-based, but NOT strictly +1 sequential;
                                entity ids may appear out of order
    u8  record_type
    u32 source_x_px          -- top-left of trigger/entity on the map
    u32 source_y_px
    u16 width_px             -- almost always 0x003A (58)
    u16 height_px            -- almost always 0x003A (58)
    8 B target_or_extra      -- warps fill it; minimal records zero it
```

Record types currently identified:

| type    | meaning                    | known lengths (bytes)      |
|---------|----------------------------|----------------------------|
| 0x00    | unclassified / mixed       | 38, 41, 48, 56, 59, 61, 62, 64, 109, 112, 117, 125, 141, 354, 733 |
| 0x01    | scripted entity / NPC      | 54, 58, 65, 68, 70, 73, 82, 122, 132, 198 |
| 0x02    | treasure chest             | 102, 109, 124, 174, 176    |
| 0x04..0x07, 0x10, 0x11, 0x16, 0x18 | minimal entity (header + 16 zero bytes) | 41 |
| 0x08    | generic / extended         | 41, 124                    |
| 0x0F    | **warp** (entrance/exit/zone/alt) | 59, 62, 69, 71, 77, 78, 83, 186, 206 |
| 0x12    | unclassified extended      | 117, 127                   |
| 0x14    | unclassified               | 46                         |
| 0x1B    | unclassified               | 51                         |

Because record lengths are type-dependent and entity ids are not
ordered, the parser uses a hybrid **length-table + DFS backtracking
walker** (`_walk_de_records`) that:

1. Tries known per-type lengths first.
2. Verifies the next position passes `_de_header_at()` (valid type, in-range rid, w/h multiples of 29, source coords < 30 k, …).
3. Backtracks if a chosen length leads to a dead-end so the entire payload is consumed in exactly `de_count` steps.
4. Falls back to a singleton-anchor heuristic walker on chunks (notably chunk 18) where ghost headers in string payloads defeat strict DFS.

##### Warp records (type 0x0F)

Warps share a trailer marker `05 00 0F` at some offset ≥ 0x10 from the
record start. The four u32/u32/u32/u8 fields that follow that marker
are the actual gameplay payload:

```
    [trailer + 3 : trailer + 7]   u32  target_lid    (chunk to load)
    [trailer + 7 : trailer + 11]  u32  target_x_px
    [trailer + 11: trailer + 15]  u32  target_y_px
    [trailer + 15: trailer + 16]  u8   sub_variant
```

`sub_variant` taxonomy (verified against in-game video):

| sub_variant | kind          | meaning                                  |
|-------------|---------------|------------------------------------------|
| 0x00        | warp_suspect  | partial-walk artifact; treat as low confidence |
| 0x01        | warp          | standard entrance                        |
| 0x02        | warp_zone     | overworld / inter-zone doorway           |
| 0x03        | warp_exit     | exit warp (NOT a chest — corrected after user verification of chunk 21 rid=1) |
| 0x04        | warp_alt      | alternate room-to-room shortcut          |

Two physical warp record layouts coexist:

- **Simple 62-byte form** (chunks 5..17, 19..35): trailer sits at offset 0x29 from the record header.
- **Extended 78/83/100-byte form** (chunk 18 = central hub): an extra
  "intermediate lid" block is inserted; trailer sits 0x3C from the
  header. `_read_warp_record()` searches for the `05 00 0F` marker
  rather than assuming a fixed offset, and falls back to scanning the
  surrounding payload up to 120 B past the record if the DE walker
  picked the shorter slice.

##### Chest records (type 0x02)

Chest records carry the tail marker `4D 00 05 00 10 [u16 entity_id] 01`.
The entity_id is a foreign key into FFBE's external item table.
Internal layouts seen:

```
    01 02 62 84 [s8 chest_offset]    -- consumables (-84 family)
    01 02 62 85 [s8 chest_offset]    -- consumables (-85 family)
    01 03 19 9C [s8 chest_offset]    -- equipment / recipes
    01 03 0A 59 [s8 chest_offset]    -- equipment / recipes
```

The `[s8]` byte is a signed offset such that `entity_id = base + s8`.
User-verified mappings for chunk 18:

| entity_id (hex) | item                       | external id  |
|-----------------|----------------------------|--------------|
| 0xD0B4          | Phoenix Down               | 101003100    |
| 0xD0B7          | Smelling Salts             | 102002100    |
| 0xD0B8          | Echo Herbs                 | 102003100    |
| 0xD0B9          | Unicorn Horn               | 102004100    |
| 0xD0CB          | Recipe for Kenpongi        | 904000400    |

##### Embedded strings

Some DE records carry Pascal-style strings (`u8 length` + ASCII bytes)
referencing animations or effects, e.g. `map_effect.ssbp`,
`room_shadow/anime`. `_extract_pascal_strings()` surfaces these into the
blueprint for later use.

---

## 4. `map_blueprint.json` shape

The parser emits one JSON document per `.bin`:

```jsonc
{
    "num_textures": 12,
    "textures": [{"atlas_id": 10000, "filename": "mapchip_0010_001.png"}, ...],
    "total_chunks": 36,
    "layers": [
        {
            "chunk_index": 0,
            "layer_id": 99,
            "grid_width": 60,
            "grid_height": 60,
            "sub_layers": [
                { "type": "visual",     "index": 0, "start_hex": "...", "end_hex_inclusive": "..." },
                { "type": "visual",     "index": 1, ... },
                { "type": "collision",  "index": N,   ... },
                { "type": "region",     "index": N+1, ... },
            ],
            "section_ranges": {
                "grid_events_section":   { "start_hex": "...", "end_hex_inclusive": "...", "size_bytes": ... },
                "static_assets_section": { ... },
                "dynamic_entities_section": { ... }
            },
            "objects": {
                "grid_events":     [ { "x": 12, "y": 18, "event_id": 1 }, ... ],
                "static_assets":   [ { "x": 696, "y": 1276, ... }, ... ],
                "dynamic_entities":[ { "record_id": 1, "record_type": "0x0F", "kind": "warp", ... }, ... ]
            }
        },
        ...
    ]
}
```

`layer_id` is the cross-chunk identity (used by warps and by
`chunk_index_for_lid()`); `chunk_index` is the position inside
`layers[]`.

---

## 5. Godot runtime consumption (`tile_map.gd`)

### 5.1 Boot sequence

1. `_ready()` adds self to group `tile_map` and calls `trigger_redraw()`.
2. If `town_id` is set, `_apply_town_paths()` resolves the bin / json / mapchip paths and forces `build_dynamic_tileset()` + redraw.
3. `build_dynamic_tileset()` re-reads the bin manifest, loads each PNG via `ResourceLoader`, calls `create_tile()` for every grid cell, and reassigns `self.tile_set`.
4. `draw_chunk(target_chunk)` reads the cached blueprint, populates the visual tile layers, then renders objects (`grid_events`, `static_assets`, `dynamic_entities`).
5. Warp `Area2D` triggers are created from `dynamic_entities[*].kind ∈ {warp, warp_zone, warp_exit, warp_alt}` at `source_x/y_px × width_px × height_px`. On `body_entered` they call `warp_to(target_lid, target_x, target_y)`.

### 5.2 Z-index scheme

The TileMap renders visual sub-layer `N` at `z_index = 2*N`, and the
corresponding static-asset container (`StaticL{N}`, a `Node2D` with
`y_sort_enabled = true`) at `z_index = 2*N + 1`. The player sits at
`z_index = 5` (above visual layer 2 / ground decor, below layer 3 /
rooftops).

### 5.3 Movement constraints from grid events

`get_grid_event_at(cell)` returns the event_id at a tile. `player.gd`
uses a 5-probe sampler (center + 4 corners at `tile_size/2 - 4` px) to
detect entry, rewrites the input direction to match the corridor axis,
snaps the body to the centerline while locked, and bypasses collision
the entire time the player stands on an event tile to prevent
depenetration from shoving them back along the stair axis.

---

## 6. Quirks & pitfalls (worth re-reading before changing anything)

- **The map.bin header is a structured 32 bytes.** Earlier docs
  described it as "`mapchip` ASCII tag followed by padding" — that
  was a misreading; the `mapchip_*` string only appears inside the
  *first texture-manifest entry's filename*, which happens to land
  near byte 28. The Python side reads the header positionally
  (`bin_common.read_file_header`). The Godot side's
  `find_manifest_offset()` is a legacy fallback that scans for the
  string; both produce the same result for every bin in the corpus.
- **No visual layer count field.** It is derived; the inter-visual
  separator vacuum is the trickiest part of the parser. Don't be
  tempted to "fix" `consume_separator()` to be stricter — chunk 26
  needs a 0-byte gap and chunks 127/128 need a pre-visual gap.
- **Static-asset offset 16 is `atlas_x_px`**, not a sprite id. Anyone
  treating it as an opaque id will see scrambled decorations.
- **Dynamic-entity record_ids are NOT sequential.** Always use the
  length-table + DFS walker; never rely on `expected_rid = prev + 1`.
- **Warp trailer offset varies (0x29 vs 0x3C+).** Always search for
  `05 00 0F`; never assume a fixed offset.
- **`sub_variant = 3` is a warp, not a chest.** This was a long-running
  mis-classification; the user verified against gameplay that chunk 21
  rid=1 (sub=3) warps to lid 104.
- **The collision overlay and the physics body must agree.** Both are
  driven by the same `debug_cells_collision` array built during
  `draw_chunk()`.
- **Player z-index 5** is correct for the interleaved scheme. Setting
  it to 2 or 4 puts the sprite under decorations; setting it ≥ 6
  draws over rooftops.
- **Blueprint cache invalidation.** Changing `blueprint_path` (or
  `town_id`, which rewrites the path) MUST go through
  `_invalidate_blueprint_cache()`; otherwise old layer data is reused.

---

## 7. Quick recipe: adding a new town

1. Drop the FFBE `map.bin` and its `mapchip_*.png` files into `{town_data_root}/{town_id}/`.
2. Run `python parse.py {town_id}` to produce `map_blueprint.json` next to the bin. The dispatcher auto-detects whether to invoke `town_parser` or `exploration_parser`.
3. From game code, call `tile_map.load_town(town_id)` (or open `Map.tscn` with the TileMap's `town_id` inspector field set).
4. In the editor, the TileMap inspector's `town_id` field gives an editor-time preview without code.

---

## 8. Event parsing & runtime

The cutscene pipeline mirrors the map pipeline but runs on a different
binary format. Three Python modules and three Godot scripts implement
it:

```
event_common.py     -- header + asset-manifest reader
event_script.py     -- opcode walker + per-opcode decoders
event_parser.py     -- orchestrates header / manifest / setup / blocks
                       and emits event_blueprint.json
event_runner.gd     -- scene root; loads blueprint, drives playback
event_actor.gd      -- per-actor sprite with walk/run animation state
Event.tscn          -- TileMap + Camera2D + DialogLayer + EventRunner
```

### 8.1 `<id>_event.bin` layout

```
offset 0x00  u32 file_size           -- matches os.stat
offset 0x04  u32 format_version      -- observed 1017..1051 (mostly 1042/1045)
offset 0x08  u32 count_a             -- unknown
offset 0x0C  u32 count_b             -- unknown
offset 0x10  u32 count_c             -- unknown
offset 0x14  u32 count_d             -- unknown
offset 0x18  u32 num_assets          -- entries that follow

offset 0x1C  asset manifest:
    repeat num_assets times:
        u16 marker           -- per-file asset slot id (0x7919.. for NPC sprites)
        u16 str_len          -- byte length of the filename
        char[str_len] name   -- ASCII (NPC sprite, .bmb/.ssbp effect, etc.)
```

After the manifest the file contains a **sparse slot/actor table region**
(mostly zeros with 12-byte records scattered at fixed offsets \-- layout
not yet decoded) and a **dense opcode-stream script** that ends at
`file_size`. The slot table region is bracketed in the blueprint as
`pre_script`; we don't decode its body, but we *do* walk a "setup"
opcode run that immediately precedes the first dialog block (see \u00a78.4).

### 8.2 Opcode frame format

```
    <op u16 BE>  <length u8>  <payload[length]>
```

Each command is therefore `3 + length` bytes. The low byte of the
opcode word is **always `0x00`** in real frames; a non-zero low byte is
the walker's "I've fallen out of the script" bail signal. `event_script.walk_script()`
yields one record per frame and emits a special `_stop` record when it
trips.

### 8.3 Currently decoded opcodes

| op    | name              | length      | notes                                                                                |
|-------|-------------------|-------------|--------------------------------------------------------------------------------------|
| 0x01  | `advance`         | 0           | Sync point: runtime waits for in-flight tweens **and** any visible dialog line.      |
| 0x02  | `short_wait`      | 2           | `u16 BE ticks` (60 ticks = 1 s).                                                     |
| 0x06  | `camera_scroll`   | 7           | `flag, i16 dx, i16 dy, pad, u8 ticks`. `flag` decides timing convention (see \u00a78.5). |
| 0x07  | `move_actor`      | 15          | `variant, pad, u16 ext_ref, actor_id, sub_flag, mode, i16 x/dx, i16 y/dy, ticks, 3 B trailer`. |
| 0x08  | `text`            | 4           | `u32 BE text_id` \u2192 looked up in `<id>_event_text.txt`.                              |
| 0x0b  | `face_actor`      | 6           | `pad u32, actor_id, direction`. Direction: 0=down 1=up 2=left 3=right.               |
| 0x0c  | `set_actor_visible` | 6        | Same actor-cmd shape as 0x07/0x0b; byte 5 is the toggle flag (semantic mapping TBD). |
| 0x0e  | `op_0x0e`         | 10          | Paired effect command. `kind = 0x06` is the full-screen fade; `kind = 0x03` is a separate cinematic toggle (currently a no-op). `variant` 0 = ON / fade-in, 1 = OFF / fade-out. `u32 BE` tail is duration in ticks. |
| 0x3a  | `scene_config`    | variable    | Container. Carries an initial-camera record (`06 00 07 00 <x BE> <y BE>`) plus embedded `move_actor` frames that place the party. Parser exposes both via `camera_position` and `embedded_moves`. |
| 0x46  | `show_bubble`     | 21          | `actor_id, bubble_id, duration, i32 offset`. `bubble_id` is a 1-based index into `map_common/emotion_icon.png` (see `BUBBLE_NAMES` in `event_script.py`).                                            |
| 0x5f  | `play_vfx`        | variable    | Pascal-style `id_str` + `id_value` + `file_str` + 18 B tail (`x, y, layer, pad, duration, end_flag`).                                                                                              |
| 0x67  | `set_move_mode`   | 1           | Single byte: `0 \u2192 mode=run`, `1 \u2192 mode=walk`. Tracked as a global flag, but in 111020301 the labels are inverted relative to the trailing `move_actor` cadence \u2014 the trailer overrides it (see \u00a78.5). |

All other opcodes are passed through as `op_0xXX` with their raw
`payload_hex`. `event_script.NAMED_OPCODES` is the registry; adding a
new decoder is a 3-line patch.

### 8.4 Parser flow (`event_parser.py`)

1. Read the 28-byte header + asset manifest (`event_common`).
2. Find the **first dialog block** by scanning for an `0x08 0x00 0x04`
   text-opcode frame whose `u32 BE` argument is either present in
   `<id>_event_text.txt` or falls in `0x010000\u20130x0fffff` (the observed
   range of real dialogue ids). This is `find_first_text_anchor()`.
3. Walk forward from the anchor; when the walker bails on a
   non-canonical opcode, jump to the next text anchor and resume.
   This is how the parser recovers from inter-block metadata without
   needing to decode it.
4. Each block carries `start_offset`, `end_offset`, `command_count`,
   `stop_record` (if any), and the full command list.
5. Walk the **setup region** that sits between the manifest and the
   first dialog block. We brute-force the start offset
   (`_walk_setup_region`): try every non-fill byte between
   `manifest_end + 12` and the first text anchor; keep the earliest
   offset whose `walk_script` consumes cleanly and lands exactly on
   the dialog block. The resulting list is the `setup_commands` array
   in the blueprint. It carries the initial `scene_config`, the
   absolute-mode spawns, the `set_move_mode`, etc.\u2014 everything the
   runtime needs to position actors before block 0 starts.
6. Aggregate an `opcode_histogram` across all blocks for triage.

### 8.5 Runtime semantics (`event_runner.gd` + `event_actor.gd`)

Folder convention: an event id `XXXXXXXY1+` runs on map `XXXXXXXY0`
(e.g. `111020301` plays on map `111020300`). The runner:

1. Loads `event_blueprint.json`, asks the sibling TileMap to
   `load_town(map_id)`.
2. Resolves which **layer** the scene lives on
   (`_resolve_event_layer`): if the map header's `initial_layer_id`
   fits the first PC1 spawn in pixel bounds, use it; otherwise pick
   the smallest layer whose `grid_width \u00d7 grid_height \u00d7 58 px`
   contains the spawn (this is how 111010101 gets routed to layer 65
   instead of the default 61).
3. Builds a black `FadeLayer` `CanvasLayer` (used by op_0x0e).
4. Sets `y_sort_enabled = true` on itself so EventActors interleave
   by `y` against each other and against TileMap StaticL nodes.
5. Plays `setup_commands` synchronously (no awaits), then walks the
   chosen dialog block.

#### Timing conventions

Two distinct `ticks` interpretations are in use; the runtime picks
between them based on context:

| context                          | convention      | example                                          |
|----------------------------------|-----------------|--------------------------------------------------|
| walking actor (trailer byte 2 == 0) | frames-per-tile | `dx = 464 (8 tiles), ticks = 50 \u2192 6.67 s`        |
| running actor (trailer byte 2 == 1) | total frames    | `dx = 464,           ticks = 50 \u2192 0.83 s`        |
| `camera_scroll` `flag = 0` (absolute target) | frames-per-tile | scenic establishing pan, distance-scaled        |
| `camera_scroll` `flag = 1` (relative delta)  | total frames    | tracks a paired running actor at the same speed |

The per-move **trailer byte 2** is the source of truth for actor
run/walk \u2014 NOT `set_move_mode`. In 111020301 `set_move_mode = run`
fires *before* the cinematic walks (trailer `01 01 00`) and
`set_move_mode = walk` fires *before* the sprint to Fina (trailer
`01 01 01`), so the global flag is intentionally ignored in
`_handle_move_actor`.

#### Synchronisation

- Animated frames (`move_actor` with `ticks > 0`, `camera_scroll` with
  `ticks > 0`) return their `Tween` and the runner stores it in
  `_pending_tweens`.
- `advance` awaits every pending tween *and* the dialog dismiss
  (`ui_accept`) before continuing. This matches the engine's "press
  through" cadence.
- `op_0x0e` fades intentionally **do not** join `_pending_tweens` \u2014
  the bin threads camera snaps and actor reposes through black, and
  the next `advance` must not wait for the fade to complete.

### 8.6 EventActor animation table

`EventActor` keeps three independent state words: `facing` (`up`,
`down`, `left`, `right`), `pose` (`idle`, `walk`, `run`), and the
move-tween itself. `POSE_FACING_TO_ANIM` cross-references them into
sprite-region names (`walk_left`, `run_down`, \u2026). `_start_move`:

* Splits a 2-D delta into an X leg then a Y leg (the engine does not
  diagonally interpolate field cutscenes).
* Picks duration per the run/walk convention above.
* Sets `pose = "run" if run else "walk"`, faces the dominant leg,
  and on tween-finish drops back to `pose = "idle"`.

### 8.7 Event-side quirks

- **Asset manifest tolerates failure.** If the manifest decode raises
  (unknown variant, truncation), the parser records
  `manifest_status = "unrecognised manifest variant: ..."`, rewinds,
  and dumps a 64-byte hex preview at `post_manifest_preview` so we can
  iterate without losing the rest of the file.
- **Scripts have multiple blocks.** Many bins carry several
  back-to-back dialog scenes plus false-positive resync blocks. The
  runtime's `block_index` export defaults to 0 and `single_block`
  defaults to `true`; raise the index to scrub through scenes when a
  bin has multiple legitimate ones.
- **Setup-walk must land exactly on dialog.** The brute-force in
  `_walk_setup_region` only accepts a start offset whose walk
  terminates at `ps_end`. This filters out runs that look syntactically
  valid but drift past the first text frame.
- **`scene_config` is a container.** Don't try to decode op_0x3a as a
  flat record \u2014 its payload ends in genuine inner opcode frames.
  `_decode_scene_config` scans for `07 00 0f` move frames and
  validates them by trailer (`010101`) to avoid false positives in the
  unknown lighting/camera prefix.
- **Bubble ids are 1-based** into a 2\u00d712 atlas where the two columns
  are facing variants. The `BUBBLE_NAMES` table records only the
  twelve distinct emotes (no separate L/R entries).

---

## 9. imHex pattern

``` cpp
#pragma endian big
#pragma array_limit 2000000
#pragma pattern_limit 5000000
#include <std/mem.pat>

// 1. THE HUNTER-SEEKER FUNCTION
fn find_manifest_offset() {
    u32 i = 0;
    while (i < 1000) {
        if (std::mem::read_unsigned(i, 1) == 0x6D && 
            std::mem::read_unsigned(i+1, 1) == 0x61 && 
            std::mem::read_unsigned(i+2, 1) == 0x70 && 
            std::mem::read_unsigned(i+3, 1) == 0x63 && 
            std::mem::read_unsigned(i+4, 1) == 0x68 && 
            std::mem::read_unsigned(i+5, 1) == 0x69 && 
            std::mem::read_unsigned(i+6, 1) == 0x70) {
            return i - 8; 
        }
        i = i + 1;
    }
    return 28; 
};

// 2. THE MANIFEST STRUCTURES
struct ManifestEntry {
    u16 atlas_id [[color("55FF55")]];
    u16 str_len [[hidden]]; 
    char filename[str_len] [[color("FFFF55")]];
};

// We wrap everything in one clean block. No more global '@' conflicts!
struct MapManifest {
    // Instead of raw bytes, we ask ImHex to read 4-byte Big Endian Integers!
    u32 header_integers[find_manifest_offset() / 4] [[color("555555"), name("Decoded Header Numbers")]];
    
    // Catch any leftover bytes just in case the header isn't perfectly divisible by 4
    u8 header_remainder[find_manifest_offset() % 4] [[hidden]];
    
    u32 num_textures [[color("FF5555"), name("Texture Count")]];
    ManifestEntry textures[num_textures];
};

// Place the massive block exactly at byte 0.
MapManifest file_manifest @ 0x00;

// 3. THE VALIDATOR
fn is_valid_id(u16 test_id) {
    if (test_id == 10000 || test_id == 65535) {
        return true;
    }
    
    u32 i = 0;
    while (i < file_manifest.num_textures) {
        if (file_manifest.textures[i].atlas_id == test_id) {
            return true;
        }
        i = i + 1;
    }
    return false;
};

// 4. THE X-RAY SCANNER
struct XRayByte {
    if (is_valid_id( (std::mem::read_unsigned($, 1) * 256) + std::mem::read_unsigned($ + 1, 1) )) {
        u32 valid_tile [[color("333333"), name("Valid Visual Tile")]]; 
    } else {
        u8 anomaly [[color("FF0055"), name("Unknown Data / Collision")]];
    }
};

XRayByte scanner[while(std::mem::size() - $ >= 4)] @ 0x0140;
```