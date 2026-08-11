@tool
extends TileMap
var file_header_num_textures = 0
var active_debug_offset: int = 0
var physics_container: StaticBody2D
var _active_chunk_data: Dictionary = {}

# --- EXPORTED FILE PATHS ---
@export_category("File Paths")
# Root folder under which each town's data lives in its own subfolder
# named after the town id, e.g. "res://assets/town_data/1102/". When
# load_town() / town_id is set, the three paths below are derived from
# "{town_data_root}/{town_id}/".
@export_dir var town_data_root: String = "res://assets/town_data" :
	set(v):
		town_data_root = v
		if town_id != "":
			_apply_town_paths()

# When set (either from the inspector or via load_town() at runtime),
# the bin / blueprint / mapchip paths are recomputed from
# town_data_root + this id, the dynamic tileset is rebuilt, and the
# active chunk is redrawn. Leave empty to use the explicit paths below.
@export var town_id: String = "" :
	set(v):
		town_id = v
		if town_id != "":
			_apply_town_paths()

@export_file("*.bin") var map_file_path: String = "res://map.bin"
@export_file("*.json") var blueprint_path: String = "res://map_blueprint.json" :
	set(v):
		blueprint_path = v
		_invalidate_blueprint_cache()
		trigger_redraw()

@export_category("Chunk Object Overlays")
@export var show_dynamic_entities: bool = true :
	set(v):
		show_dynamic_entities = v
		trigger_redraw()

@export var show_grid_events: bool = false :
	set(v):
		show_grid_events = v
		trigger_redraw()

@export var show_static_placeholders: bool = false :
	set(v):
		show_static_placeholders = v
		trigger_redraw()

@export_range(0.05, 8.0, 0.05) var npc_sprite_scale: float = 2.0 :
	set(v):
		npc_sprite_scale = v
		trigger_redraw()

@export_category("Map Settings")
@export var target_chunk: int = 0 :
	set(v):
		if target_chunk == v: return # Breaks the loop!
		target_chunk = v
		trigger_redraw()

@export_global_dir var mapchip_folder: String = "res://mapchips" :
	set(v): mapchip_folder = v

@export var tile_size: int = 58 :
	set(v): tile_size = v

@export var generate_tileset: bool = false :
	set(v):
		if v:
			generate_tileset = false
			build_dynamic_tileset()

@export_group("Debug Visuals")
@export var show_collision: bool = false :
	set(v):
		show_collision = v
		# Rebuild the CollisionOverlay child node so toggling in the
		# inspector reflects immediately without a full redraw.
		if is_inside_tree():
			_draw_collision_overlay()
		queue_redraw()

@export var collision_color: Color = Color(1.0, 0.0, 0.0, 0.5) # Semi-transparent Red

# Add this to your internal variables!
var debug_cells_collision: Array[Vector2i] = []
@export var show_grid: bool = false :
	set(v):
		show_grid = v
		queue_redraw()

@export var grid_color: Color = Color(1.0, 1.0, 1.0, 0.15) : # Faint white by default
	set(v):
		grid_color = v
		if show_grid: queue_redraw()

@export_flags("Layer 0", "Layer 1", "Layer 2", "Layer 3", "Layer 4", "Layer 5", "Layer 6", "Layer 7", "Layer 8", "Layer 9", "Layer 10", "Layer 11") var visible_layers: int = 4095 :
	set(v):
		visible_layers = v
		update_layer_visibility()

# --- INTERNAL VARIABLES ---
# map_width / map_height are populated from the blueprint chunk data; they
# are not user-editable so they live here instead of as @export properties.
var map_width: int = 0
var map_height: int = 0
var id_map = {}
var valid_ids = []
# Maps Vector2i tile coord -> event_id (1=TL-BR stair, 2=BL-TR stair,
# 3=ladder body, 4=ladder anchor). Rebuilt every chunk redraw and
# queried by the player controller to constrain movement.
var grid_events_lookup: Dictionary = {}

# Cached parse of the blueprint JSON. Avoids re-reading the file on every
# chunk fetch and provides the data backing chunk_index_for_lid().
var _blueprint_cache: Dictionary = {}
# layer_id (int) -> chunk index in _blueprint_cache["layers"]. Populated
# the first time the blueprint is loaded; used by warp_to() to resolve a
# warp target's layer_id back to the chunk it lives in.
var _lid_to_chunk: Dictionary = {}

func _ready():
	add_to_group("tile_map")
	# Minimap is owned by the town scene (town_map.gd) rather than the
	# TileMap itself, so reusing this script in non-town scenes (e.g.
	# Event.tscn) doesn't drag a minimap into the HUD. The bake in
	# _draw_chunk() looks the minimap up via the "minimap" group and
	# is a no-op when none exists.
	# Only auto-draw if a real map has been wired up. Otherwise we hit
	# the default res://map_blueprint.json placeholder (which doesn't
	# exist in this project) and spam an error before EventRunner has a
	# chance to call load_town().
	if town_id != "" or FileAccess.file_exists(blueprint_path):
		trigger_redraw()

# Public entry point: switch this TileMap to render the town with the
# given id. Resolves all three asset paths under town_data_root, rebuilds
# the dynamic tileset from the new bin's manifest and redraws the active
# chunk. Safe to call before _ready() (the redraw is no-op until the
# node is in the tree).
#
# Expected folder layout (per town):
#   {town_data_root}/{town_id}/
#       map.bin
#       map_blueprint.json
#       mapchip_*.png       <- referenced by filenames in map.bin's manifest
func load_town(id: String) -> void:
	town_id = id  # setter calls _apply_town_paths()

# Rebuilds map_file_path / blueprint_path / mapchip_folder from
# town_data_root + town_id, then forces a tileset rebuild and redraw.
# Called by the town_id and town_data_root setters; not meant to be
# called directly from outside.
func _apply_town_paths() -> void:
	if town_id == "":
		return
	var base := town_data_root.rstrip("/") + "/" + town_id
	map_file_path = base + "/map.bin"
	# All mapchip PNGs live alongside map.bin in the same town folder.
	# Set this BEFORE blueprint_path: blueprint_path's setter fires a
	# trigger_redraw() which can build the dynamic tileset on demand;
	# that build uses mapchip_folder, so it must already point at the
	# new town or several atlas sources will be skipped (resulting in
	# "No TileSet atlas source with id N" spam from get_source()).
	mapchip_folder = base
	blueprint_path = base + "/map_blueprint.json"
	_invalidate_blueprint_cache()
	if is_inside_tree():
		# Regenerate the tileset from the new bin's manifest, then redraw.
		# build_dynamic_tileset() reassigns self.tile_set, replacing
		# whatever was baked into the scene.
		build_dynamic_tileset()
		# At runtime, honour the spawn the bin's file header dictates:
		# warp to the initial layer_id at the initial (x, y). Editor /
		# @tool previews fall through to the plain redraw of the
		# user-selected target_chunk for inspector iteration.
		if not Engine.is_editor_hint() and _ensure_blueprint_loaded():
			var init_lid := int(_blueprint_cache.get("initial_layer_id", -1))
			if init_lid >= 0 and chunk_index_for_lid(init_lid) >= 0:
				var ix := int(_blueprint_cache.get("initial_player_x", 0))
				var iy := int(_blueprint_cache.get("initial_player_y", 0))
				print("Initial spawn from bin header: lid=%d at (%d, %d)" % [init_lid, ix, iy])
				# Defer so any player node still resolving its own
				# _ready (and thus group registration) is in the tree
				# by the time we look it up. The chunk is drawn
				# synchronously regardless (warp_to sets target_chunk),
				# so callers that don't have a player (e.g. EventRunner)
				# still get the right layer visible immediately.
				warp_to(init_lid, ix, iy)
				return
		trigger_redraw()

func get_grid_event_at(cell: Vector2i) -> int:
	return int(grid_events_lookup.get(cell, 0))

# Returns the chunk index for a given layer_id, or -1 if the layer_id
# isn't present in this map bin (e.g. external lids that live in other
# map files).
func chunk_index_for_lid(lid: int) -> int:
	_ensure_blueprint_loaded()
	return int(_lid_to_chunk.get(lid, -1))

func trigger_redraw():
	if not is_node_ready(): return
	draw_chunk(target_chunk)

# --- THE NEW BINARY HEADER PARSER ---
func read_manifest_from_binary():
	id_map.clear()
	valid_ids.clear()
	valid_ids.append(10000) # Empty Grass
	valid_ids.append(65535) # Null/Transparent
	
	if not FileAccess.file_exists(map_file_path): 
		print("ERROR: Cannot find Map BIN at -> ", map_file_path)
		return false
		
	var file = FileAccess.open(map_file_path, FileAccess.READ)
	if file == null: return false
		
	file.big_endian = true 
	
	var header_offset = find_manifest_offset(file)
	if header_offset == -1:
		print("ERROR: Could not find 'mapchip' in the header!")
		return false
		
	file.seek(header_offset)
	var num_textures = file.get_32()
	print("--- READING BINARY HEADER ---")
	print("Header declares ", num_textures, " textures.")
	file_header_num_textures = num_textures
	
	var godot_id = 0
	
	for i in range(num_textures):
		var atlas_id = file.get_16()
		var str_length = file.get_16()
		
		# Read the exact string length to pull the image name directly out of the hex!
		var filename = file.get_buffer(str_length).get_string_from_ascii()
		
		id_map[atlas_id] = godot_id
		valid_ids.append(atlas_id)
		
		print("Assigned ID ", atlas_id, " -> Godot Source: ", godot_id, " (", filename, ")")
		godot_id += 1
	print("--- HEADER PARSING COMPLETE ---")
	return true

# --- THE HUNTER-SEEKER HEADER SCANNER ---
func find_manifest_offset(file: FileAccess) -> int:
	file.seek(0)
	var header_bytes = file.get_buffer(500) # Read the first 500 bytes
	var search_str = "mapchip".to_ascii_buffer()
	
	# Scan byte-by-byte for the word "mapchip"
	for i in range(header_bytes.size() - search_str.size()):
		var is_match = true
		
		for j in range(search_str.size()):
			if header_bytes[i+j] != search_str[j]:
				is_match = false
				break
				
		if is_match:
			# We found "mapchip"! The Texture Count is always exactly 8 bytes behind the 'm'
			var true_offset = i - 8
			return true_offset
			
	return -1 # Failed to find it

func update_layer_visibility():
	if not is_node_ready(): return
	for i in range(12):
		var is_checked = (visible_layers & (1 << i)) != 0
		if get_layers_count() > i:
			set_layer_enabled(i, is_checked)


func draw_single_layer(layer_index: int, offset: int):
	active_debug_offset = offset
	if not read_manifest_from_binary(): return
		
	var file = FileAccess.open(map_file_path, FileAccess.READ)
	if file == null: return
		
	clear_layer(layer_index)
	file.big_endian = true 
	
	# --- NORMAL MAP DRAWING LOGIC (Runs if Gallery Mode is OFF) ---
	file.seek(offset)
	var anomalies = 0
	
	for y in range(map_height):
		var x = 0
		while x < map_width:
			if file.get_position() >= file.get_length(): 
				update_layer_visibility()
				return
				
			var atlas_id = file.get_16()
			var sprite_idx = file.get_16()
			
			if id_map.has(atlas_id):
				var source_id = id_map[atlas_id]
				var atlas_x = sprite_idx % 17
				var atlas_y = int(sprite_idx / 17) 
				set_cell(layer_index, Vector2i(x, y), source_id, Vector2i(atlas_x, atlas_y))
				
			x += 1
		
	print("SUCCESS: Layer ", layer_index, " Drawn | Offset: ", offset, " | Healed: ", anomalies)
	update_layer_visibility()

func build_dynamic_tileset():
	if not FileAccess.file_exists(map_file_path):
		print("ABORTING: Cannot find Map BIN at -> ", map_file_path)
		return
		
	print("--- GENERATING DYNAMIC TILESET ---")
	var file = FileAccess.open(map_file_path, FileAccess.READ)
	file.big_endian = true 
	
	var header_offset = find_manifest_offset(file)
	if header_offset == -1: return
		
	file.seek(header_offset)
	var num_textures = file.get_32()
	
	# Create a brand new TileSet in memory
	var new_tileset = TileSet.new()
	new_tileset.tile_size = Vector2i(tile_size, tile_size)
	
	var godot_id = 0
	var success_count = 0
	
	for i in range(num_textures):
		var atlas_id = file.get_16()
		var str_length = file.get_16()
		var filename = file.get_buffer(str_length).get_string_from_ascii()
		
		# Clean up the path just in case
		var full_path = mapchip_folder + "/" + filename
		full_path = full_path.replace("//", "/")
		full_path = full_path.replace("res:/", "res://")
		
		if ResourceLoader.exists(full_path):
			var tex = load(full_path)
			var source = TileSetAtlasSource.new()
			source.texture = tex
			source.texture_region_size = Vector2i(tile_size, tile_size)
			
			# Godot 4 requires us to manually "create" each tile in the atlas grid
			var grid_w = tex.get_width() / tile_size
			var grid_h = tex.get_height() / tile_size
			for tx in range(grid_w):
				for ty in range(grid_h):
					source.create_tile(Vector2i(tx, ty))
			
			# Add it to the TileSet using the exact sequential godot_id
			new_tileset.add_source(source, godot_id)
			print("Loaded: ", filename, " as Source ID: ", godot_id)
			success_count += 1
		else:
			print("MISSING IMAGE: Could not find ", full_path)
			
		godot_id += 1
		
	# Assign our newly built TileSet to the active TileMap
	self.tile_set = new_tileset
	print("--- TILESET GENERATION COMPLETE! Loaded ", success_count, "/", num_textures, " images ---")

func _input(event):
	# Only trigger when the Left Mouse Button is clicked
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		
		# Convert the mouse pixel position into Godot grid coordinates
		var local_pos := get_local_mouse_position()
		var clicked_cell = local_to_map(local_pos)
		var cx = clicked_cell.x
		var cy = clicked_cell.y

		# Top-left pixel of that cell, in the same coordinate space used by
		# the blueprint's static_assets x/y fields (cell index * tile_size).
		var px: int = int(cx) * tile_size
		var py: int = int(cy) * tile_size
		print("Click @ grid (", cx, ", ", cy, ") top-left px (", px, ", ", py, ")")

		# List every static_asset record in the active chunk whose bounding
		# box contains this clicked cell. Helps verify which record is
		# *supposed* to be rendered here (vs. which sprite is visually on top).
		if not _active_chunk_data.is_empty() \
				and _active_chunk_data.has("objects") \
				and _active_chunk_data["objects"].has("static_assets"):
			var statics_dbg: Array = _active_chunk_data["objects"]["static_assets"]
			# Use the clicked cell's pixel midpoint so a tile-aligned record
			# (record_x = cell_x * tile_size) counts as a match.
			var mx: int = px + (tile_size / 2)
			var my: int = py + (tile_size / 2)
			var matches := []
			for i in range(statics_dbg.size()):
				var rec: Dictionary = statics_dbg[i]
				var rx: int = int(rec["x"])
				var ry: int = int(rec["y"])
				var rs: float = float(int(rec.get("scale", 100))) / 100.0
				var rw: int = int(round(int(rec["width"]) * rs))
				var rh: int = int(round(int(rec["height"]) * rs))
				if mx >= rx and mx < rx + rw and my >= ry and my < ry + rh:
					matches.append({"idx": i, "rec": rec})
			if matches.is_empty():
				print("  no static_asset bounding box contains this cell")
			else:
				print("  ", matches.size(), " static_asset record(s) overlap this cell:")
				for m in matches:
					var r: Dictionary = m["rec"]
					print("    [#", m["idx"], "] x=", r["x"], " y=", r["y"],
						" w=", r["width"], " h=", r["height"],
						" atlas_id=", r["atlas_id"],
						" atlas=(", r["atlas_x"], ",", r["atlas_y"], ")",
						" layer=", r.get("layer", 0),
						" layer_flags=", r.get("layer_flags", 0),
						" scale=", r.get("scale", 100))

		# Ensure we are clicking inside the actual map boundaries
		if cx >= 0 and cx < map_width and cy >= 0 and cy < map_height:
			probe_tile_data(cx, cy)

func probe_tile_data(cx: int, cy: int):
	var file = FileAccess.open(map_file_path, FileAccess.READ)
	if file == null: return
	file.big_endian = true 
	
	# Calculate the exact byte address in the .bin file
	var tile_index = (cy * map_width) + cx
	var byte_address = active_debug_offset + (tile_index * 4)
	
	# Jump to that exact address and read the 4 bytes
	file.seek(byte_address)
	var atlas_id = file.get_16()
	var sprite_id = file.get_16()
	
	# Format the output into Hex so it matches ImHex perfectly
	var hex_address = "%X" % byte_address
	var hex_atlas = "%04X" % atlas_id
	var hex_sprite = "%04X" % sprite_id
	
	print("--- HEX PROBE ---")
	print("Grid Coordinate: (", cx, ", ", cy, ")")
	print("Linear Index:    ", tile_index)
	print("BIN Offset:      0x", hex_address, " (Decimal: ", byte_address, ")")
	print("Raw Hex Data:    ", hex_atlas, " ", hex_sprite)
	
	if atlas_id == 65535:
		print("Status:          BLANK / TRANSPARENT (FF FF)")
	elif atlas_id == 10000:
		print("Status:          INVISIBLE WALL (27 10)")
	elif id_map.has(atlas_id):
		print("Status:          VALID TILE")
	else:
		print("Status:          UNKNOWN / ANOMALY")
	print("-----------------")

func _draw():
	if map_width == 0 or map_height == 0:
		return

	if not show_grid:
		return
		
	# Calculate the absolute pixel boundaries of the map
	var max_x_pixel = map_width * tile_size
	var max_y_pixel = map_height * tile_size
	
	# Draw Vertical Lines
	for x in range(map_width + 1):
		var start_pos = Vector2(x * tile_size, 0)
		var end_pos = Vector2(x * tile_size, max_y_pixel)
		draw_line(start_pos, end_pos, grid_color, 1.0)
		
	# Draw Horizontal Lines
	for y in range(map_height + 1):
		var start_pos = Vector2(0, y * tile_size)
		var end_pos = Vector2(max_x_pixel, y * tile_size)
		draw_line(start_pos, end_pos, grid_color, 1.0)
		
	# Optional: Draw a solid red border around the absolute edge of the map
	var border_rect = Rect2(0, 0, max_x_pixel, max_y_pixel)
	draw_rect(border_rect, Color(1.0, 0.0, 0.0, 0.8), false, 2.0)
	# NOTE: collision overlay is rendered via the CollisionOverlay child
	# Node2D (created in draw_chunk) so it sits on top of ChunkOverlays
	# and StaticAssets, not in _draw() which is gated by show_grid above.

# Loads and parses the blueprint JSON into _blueprint_cache (and rebuilds
# the lid->chunk lookup) on first use. Subsequent calls are no-ops unless
# the cache is empty (e.g. after _invalidate_blueprint_cache()).
func _ensure_blueprint_loaded() -> bool:
	if not _blueprint_cache.is_empty():
		return true
	if not FileAccess.file_exists(blueprint_path):
		print("ERROR: Cannot find Blueprint JSON!")
		return false
	var file = FileAccess.open(blueprint_path, FileAccess.READ)
	if file == null:
		print("ERROR: Failed to open Blueprint JSON!")
		return false
	var json_string = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		print("JSON Parse Error: ", json.get_error_message())
		return false
	_blueprint_cache = json.get_data()
	# Build the layer_id -> chunk index lookup so the warp system can
	# resolve cross-chunk targets without re-scanning every layer.
	_lid_to_chunk.clear()
	var layers: Array = _blueprint_cache.get("layers", [])
	for i in range(layers.size()):
		var L: Dictionary = layers[i]
		if L.has("layer_id"):
			_lid_to_chunk[int(L["layer_id"])] = i
	return true

# Drops the cached parse so the next get_chunk_data() / chunk_index_for_lid()
# re-reads the file. Call after blueprint_path changes.
func _invalidate_blueprint_cache() -> void:
	_blueprint_cache = {}
	_lid_to_chunk.clear()

func get_chunk_data(chunk_index: int) -> Dictionary:
	if not _ensure_blueprint_loaded():
		return {}
	var layers: Array = _blueprint_cache.get("layers", [])
	if chunk_index < 0 or chunk_index >= layers.size():
		print("ERROR: Chunk index out of bounds!")
		return {}
	return layers[chunk_index]

func draw_chunk(chunk_index: int):
	var chunk_data = get_chunk_data(chunk_index)
	if chunk_data.is_empty(): return
	_active_chunk_data = chunk_data
	
	if map_width != chunk_data["grid_width"]: 
		map_width = chunk_data["grid_width"]
	if map_height != chunk_data["grid_height"]: 
		map_height = chunk_data["grid_height"]
	
	print("--- DRAWING CHUNK ", chunk_index, " (Layer ID: ", chunk_data["layer_id"], ") ---")
	
	if not read_manifest_from_binary(): return
	
	var bin_file = FileAccess.open(map_file_path, FileAccess.READ)
	if bin_file == null:
		print("ERROR: Could not open map.bin!")
		return
		
	bin_file.big_endian = true 
	
	# Clear all old data
	clear() 
	debug_cells_collision.clear()

	# Remove any leftover overlay/asset nodes from a previous chunk so
	# dynamic-entity / grid-event / static markers don't accumulate when
	# switching layers. queue_free() is deferred, so use free() here to
	# guarantee the old children are gone before we re-create new ones.
	for child_name in ["ChunkOverlays", "StaticAssets", "ScaledStatics", "CollisionOverlay", "WarpTriggers"]:
		for n in get_children():
			if n.name == child_name:
				remove_child(n)
				n.free()
	# Per-layer static containers ("StaticL0", "StaticL1", ...) are
	# created fresh each chunk; remove any leftover from the previous one.
	for n in get_children():
		if String(n.name).begins_with("StaticL"):
			remove_child(n)
			n.free()
	
	# Rebuild the grid-event tile lookup so the player controller can
	# query stair/ladder constraints at runtime.
	grid_events_lookup.clear()
	if chunk_data.has("objects") and chunk_data["objects"].has("grid_events"):
		for ev in chunk_data["objects"]["grid_events"]:
			grid_events_lookup[Vector2i(int(ev["x"]), int(ev["y"]))] = int(ev["event_id"])

	# Make sure the TileMap has at least one Godot layer per visual
	# sublayer this chunk needs. Map.tscn declares 8 layers inline, but
	# Event.tscn (and any other scene that instances a bare TileMap)
	# only ships with layer 0, so higher sublayers would silently be
	# dropped by set_cell(). Auto-extend here so draw_chunk works
	# regardless of how the host scene was authored.
	var needed_layers := 1
	for sl in chunk_data["sub_layers"]:
		if sl["type"] == "visual":
			needed_layers = max(needed_layers, int(sl["index"]) + 1)
	while get_layers_count() < needed_layers:
		var new_idx := get_layers_count()
		add_layer(new_idx)
		set_layer_name(new_idx, "Layer%d" % new_idx)
		# Mirror Map.tscn's z_index convention (visual sublayer N at
		# z = 2*N) so statics interleaved at 2*N + 1 sit on top.
		set_layer_z_index(new_idx, 2 * new_idx)

	for sub_layer in chunk_data["sub_layers"]:
		var start_offset = sub_layer["start_hex"].hex_to_int()
		bin_file.seek(start_offset)
		
		# --- RENDER 4-BYTE VISUAL TILES ---
		if sub_layer["type"] == "visual":
			var godot_layer_index = sub_layer["index"]
			for y in range(map_height):
				var x = 0
				while x < map_width:
					if bin_file.get_position() >= bin_file.get_length(): return
						
					var atlas_id = bin_file.get_16()
					var sprite_idx = bin_file.get_16()
					
					if id_map.has(atlas_id):
						var source_id = id_map[atlas_id]
						var atlas_x = sprite_idx % 17
						var atlas_y = int(sprite_idx / 17) 
						set_cell(godot_layer_index, Vector2i(x, y), source_id, Vector2i(atlas_x, atlas_y))
						
					x += 1
			# Give every visual sublayer a z_index of (2 * its index) so
			# statics can be interleaved at (2 * layer + 1).
			set_layer_z_index(godot_layer_index, 2 * godot_layer_index)
			print("Successfully drew Visual Layer ", godot_layer_index)
			
		# --- RENDER 1-BYTE COLLISION MAP ---
		elif sub_layer["type"] == "collision":
			for y in range(map_height):
				for x in range(map_width):
					if bin_file.get_position() >= bin_file.get_length(): return
					
					# Read exactly 1 byte
					var collision_flag = bin_file.get_8()
					
					# 1 represents a solid wall in Alim's engine
					if collision_flag == 1:
						debug_cells_collision.append(Vector2i(x, y))
						
			print("Successfully parsed Collision Map")
	
	# --- GENERATE PHYSICAL WALLS ---
	# 1. Clean up the old walls if we load a new map chunk
	if is_instance_valid(physics_container):
		physics_container.queue_free()
		
	# 2. Create a new master body to hold all the collision shapes
	physics_container = StaticBody2D.new()
	add_child(physics_container)
	
	# 3. Spawn a physics square for every solid tile
	for cell in debug_cells_collision:
		var coll_shape = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(tile_size, tile_size)
		coll_shape.shape = rect
		
		# Position the shape based on the grid (adding half the size centers it properly)
		coll_shape.position = Vector2(cell.x * tile_size + (tile_size / 2.0), cell.y * tile_size + (tile_size / 2.0))
		
		physics_container.add_child(coll_shape)
	
	# --- DRAW STATIC ASSETS via composite registry ---
	if chunk_data.has("objects") and chunk_data["objects"].has("static_assets"):
		# If the dynamic tileset hasn't been built yet (e.g. draw_chunk
		# was triggered by a stale target_chunk setter before
		# build_dynamic_tileset() ran), do that now. Without this,
		# tile_set.get_source(src) below crashes with a null deref.
		if tile_set == null:
			print("draw_chunk: tile_set is null; building dynamic tileset on demand")
			build_dynamic_tileset()
		if tile_set == null:
			push_warning("draw_chunk: tile_set still null after build; skipping static assets")
			return
		# Clean up any previous placeholder container.
		var old_container = get_node_or_null("StaticAssets")
		if old_container: old_container.queue_free()

		var statics: Array = chunk_data["objects"]["static_assets"]

		# Static assets are grouped by their `layer` field (formerly the
		# low byte of the u16 "variant" word in the .bin; the high byte
		# is now exposed separately as `layer_flags` for future use).
		# Collect the set of layer indices that appear in this chunk so
		# we can build one y-sorted container per layer below.
		var layer_offsets := {}
		for obj in statics:
			layer_offsets[int(obj.get("layer", 0))] = true
		var offsets_sorted: Array = layer_offsets.keys()
		offsets_sorted.sort()

		# All static assets are rendered as Sprite2D children of a
		# per-layer Node2D container. Each container has:
		#   - y_sort_enabled = true   (lower-on-screen sprites draw in front)
		#   - z_index = 2*layer + 1   (interleaved with visual sublayers,
		#     where visual sublayer N has z_index 2*N)
		var layer_containers := {}
		for v in offsets_sorted:
			var c := Node2D.new()
			c.name = "StaticL%d" % int(v)
			c.y_sort_enabled = true
			c.z_index = 2 * int(v) + 1
			add_child(c)
			layer_containers[int(v)] = c

		var painted := 0
		var missing_atlases := {}

		for obj in statics:
			# As of the static_asset schema fix, every record carries direct
			# atlas pixel coordinates (atlas_x, atlas_y) plus its blit size
			# (width, height). The data IS the placement.
			var atlas_id := int(obj["atlas_id"])
			if not id_map.has(atlas_id):
				missing_atlases[atlas_id] = int(missing_atlases.get(atlas_id, 0)) + 1
				continue
			var src := int(id_map[atlas_id])
			var ax_px := int(obj["atlas_x"])
			var ay_px := int(obj["atlas_y"])
			var w_px := int(obj["width"])
			var h_px := int(obj["height"])
			var dst_x := int(obj["x"])
			var dst_y := int(obj["y"])
			var scale_pct: int = int(obj.get("scale", 100))
			var asset_layer := int(obj.get("layer", 0))
			var flags_c := int(obj.get("flags_c", 0))
			var flip_h: bool = (flags_c & 256) != 0

			var ts_source := tile_set.get_source(src) as TileSetAtlasSource
			if ts_source == null:
				continue
			var tex: Texture2D = ts_source.texture
			if tex == null:
				continue

			var sprite := Sprite2D.new()
			sprite.texture = tex
			sprite.region_enabled = true
			sprite.region_rect = Rect2(ax_px, ay_px, w_px, h_px)
			sprite.centered = false
			var sf: float = scale_pct / 100.0
			# To flip horizontally while keeping the bounding box at
			# the same on-screen rect, negate the X scale and shift
			# the top-left pivot to where the right edge would be.
			if flip_h:
				sprite.scale = Vector2(-sf, sf)
				sprite.position = Vector2(dst_x + w_px * sf, dst_y)
			else:
				sprite.scale = Vector2(sf, sf)
				sprite.position = Vector2(dst_x, dst_y)

			var c: Node2D = layer_containers[asset_layer]
			c.add_child(sprite)
			painted += 1

		print("Static assets: %d records -> %d sprites | layers=%s | missing atlases: %d" % [
			statics.size(), painted, str(offsets_sorted), missing_atlases.size()
		])

		# Optional debug overlay (the old green rects with id labels).
		if show_static_placeholders:
			var object_container := Node2D.new()
			object_container.name = "StaticAssets"
			add_child(object_container)
			for obj in statics:
				var rect := ColorRect.new()
				rect.size = Vector2(obj["width"], obj["height"])
				rect.position = Vector2(obj["x"], obj["y"])
				rect.color = Color(0.2, 0.8, 0.2, 0.5)
				rect.z_index = int(obj.get("render_flag", 1))
				var label := Label.new()
				label.text = "%d @(%d,%d) x%d%%" % [int(obj["atlas_id"]), int(obj["atlas_x"]), int(obj["atlas_y"]), int(obj.get("scale", 100))]
				label.add_theme_font_size_override("font_size", 10)
				rect.add_child(label)
				object_container.add_child(rect)

	# --- DRAW CHUNK OBJECT OVERLAYS ---
	# Shows this chunk's grid events and/or dynamic entities, sourced
	# directly from chunk_data["objects"] in the blueprint JSON.
	_draw_chunk_overlays(chunk_data)

	# --- SPAWN NPC ANIMATED SPRITES ---
	# Visual-only AnimatedSprite2D per scripted_entity that carries a
	# `sprite_id` in the blueprint.
	_spawn_npcs(chunk_data)

	# --- SPAWN TREASURE CHESTS ---
	_spawn_chests(chunk_data)

	# --- DRAW COLLISION OVERLAY (on top of everything) ---
	_draw_collision_overlay()

	# --- PUSH WALKABLE TEXTURE TO MINIMAP ---
	_update_minimap()

	# --- BUILD WARP TRIGGERS (only when running, not in @tool editor) ---
	if not Engine.is_editor_hint():
		_build_warp_triggers(chunk_data)

	update_layer_visibility()
	queue_redraw()


func _update_minimap() -> void:
	# The minimap CanvasLayer is spawned as a child of this TileMap in
	# _ready(). At edit-time / @tool it won't exist, which is fine --
	# we just skip the bake.
	if not is_inside_tree():
		return
	var minimap_node := get_tree().get_first_node_in_group("minimap")
	if minimap_node == null:
		return
	if map_width <= 0 or map_height <= 0:
		return
	minimap_node.set_walkable_map(map_width, map_height, debug_cells_collision)
	_push_minimap_markers(minimap_node)


# Build the category markers for the active chunk and hand them to the
# minimap. Whitelisted kinds: scripted entities (NPCs), warp doors (regular +
# alt) and treasure chests. Unknown warp variants are intentionally skipped to
# keep the minimap focused.
func _push_minimap_markers(minimap_node: Node) -> void:
	const ALLOWED := ["scripted_entity", "warp", "warp_alt", "warp_zone", "chest"]
	var markers: Array = []
	if _active_chunk_data.has("objects"):
		var objs: Dictionary = _active_chunk_data["objects"]
		var entities: Array = objs.get("dynamic_entities", [])
		for e in entities:
			var kind := String(e.get("kind", ""))
			if not ALLOWED.has(kind):
				continue
			if not (e.has("source_x_px") and e.has("source_y_px")):
				continue
			var sx: float = float(e["source_x_px"])
			var sy: float = float(e["source_y_px"])
			var sw: float = float(e.get("width_px", tile_size))
			var sh: float = float(e.get("height_px", tile_size))
			# Convert pixel-space rect center to grid-space center.
			var gx: float = (sx + sw * 0.5) / float(tile_size)
			var gy: float = (sy + sh * 0.5) / float(tile_size)
			markers.append({
				"grid_pos": Vector2(gx, gy),
				"color": minimap_node.color_for_kind(kind),
			})
	minimap_node.set_markers(markers)


func _draw_collision_overlay() -> void:
	# Remove any prior collision overlay node so toggling/redraw stays clean.
	for n in get_children():
		if n.name == "CollisionOverlay":
			remove_child(n)
			n.free()

	if not show_collision:
		return
	if debug_cells_collision.is_empty():
		return

	var container := Node2D.new()
	container.name = "CollisionOverlay"
	# Higher than ChunkOverlays (1000) so collision always sits on top.
	container.z_index = 2000
	container.z_as_relative = false
	add_child(container)

	for cell in debug_cells_collision:
		var rect := ColorRect.new()
		rect.size = Vector2(tile_size, tile_size)
		rect.position = Vector2(cell.x * tile_size, cell.y * tile_size)
		rect.color = collision_color
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(rect)

	print("Collision overlay: drew %d solid cells (z=2000)" % debug_cells_collision.size())


func _draw_chunk_overlays(chunk_data: Dictionary) -> void:
	# Always remove any prior overlay node so toggling/redraw stays clean.
	# Using free() (not queue_free) and iterating all children handles the
	# case where multiple ChunkOverlays survived from rapid redraws.
	for n in get_children():
		if n.name == "ChunkOverlays":
			remove_child(n)
			n.free()

	if not (show_dynamic_entities or show_grid_events):
		return
	if not chunk_data.has("objects"):
		print("Chunk overlays: chunk has no 'objects' block in blueprint")
		return

	var objects: Dictionary = chunk_data["objects"]
	var container := Node2D.new()
	container.name = "ChunkOverlays"
	container.z_index = 1000  # draw on top of everything
	add_child(container)

	if show_grid_events and objects.has("grid_events"):
		_render_grid_events(container, objects["grid_events"])

	if show_dynamic_entities and objects.has("dynamic_entities"):
		_render_dynamic_entities(container, objects["dynamic_entities"])


func _render_grid_events(container: Node2D, events: Array) -> void:
	# Grid events are stored with x/y in TILE coordinates and a single
	# event_id byte that encodes a movement constraint:
	#   id 1 -> diagonal stair, top-left <-> bottom-right
	#   id 2 -> diagonal stair, bottom-left <-> top-right
	#   id 3 -> vertical ladder body (allows up/down only)
	#   id 4 -> ladder anchor (top or bottom entry tile)
	#   other -> unknown, draw magenta with raw id
	print("Chunk overlays: drawing %d grid events" % events.size())
	for i in range(events.size()):
		var ev: Dictionary = events[i]
		var tx := int(ev["x"])
		var ty := int(ev["y"])
		var eid := int(ev["event_id"])

		var fill := Color(1.0, 0.0, 1.0, 0.45)
		var glyph := "?"
		match eid:
			1:
				fill = Color(0.95, 0.55, 0.10, 0.45) # orange
				glyph = "\u2198" # ↘
			2:
				fill = Color(0.20, 0.75, 0.95, 0.45) # cyan
				glyph = "\u2197" # ↗
			3:
				fill = Color(0.30, 0.85, 0.35, 0.45) # green
				glyph = "\u2195" # ↕
			4:
				fill = Color(0.95, 0.85, 0.20, 0.55) # yellow
				glyph = "\u25A0" # ■

		var rect := ColorRect.new()
		rect.size = Vector2(tile_size, tile_size)
		rect.position = Vector2(tx * tile_size, ty * tile_size)
		rect.color = fill
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(rect)

		var glyph_label := Label.new()
		glyph_label.text = glyph
		glyph_label.add_theme_font_size_override("font_size", int(tile_size * 0.7))
		glyph_label.add_theme_color_override("font_color", Color.WHITE)
		glyph_label.add_theme_color_override("font_outline_color", Color.BLACK)
		glyph_label.add_theme_constant_override("outline_size", 4)
		glyph_label.size = Vector2(tile_size, tile_size)
		glyph_label.position = Vector2(tx * tile_size, ty * tile_size)
		glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(glyph_label)

		var id_label := Label.new()
		id_label.text = "id=%d" % eid
		id_label.add_theme_font_size_override("font_size", 9)
		id_label.add_theme_color_override("font_color", Color.WHITE)
		id_label.add_theme_color_override("font_outline_color", Color.BLACK)
		id_label.add_theme_constant_override("outline_size", 3)
		id_label.position = Vector2(tx * tile_size + 2, ty * tile_size + 2)
		id_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(id_label)


func _render_dynamic_entities(container: Node2D, entities: Array) -> void:
	# Dynamic entities come straight from the blueprint's objects.dynamic_entities.
	# Known record types:
	#   0x0F -> warp / chest / warp_alt (62 bytes) -- has source_x_px/source_y_px
	#           in pixel coords plus width_px/height_px, target_lid/target_x/target_y.
	#   0x01 -> scripted_entity (64 bytes) -- no decoded position yet, raw_hex only.
	#   unknown -> raw_hex_tail blob, no decoded position.
	var palette := [
		Color(1.0, 0.2, 0.2, 0.55),
		Color(0.2, 0.6, 1.0, 0.55),
		Color(1.0, 0.85, 0.1, 0.55),
		Color(0.4, 1.0, 0.4, 0.55),
		Color(1.0, 0.4, 1.0, 0.55),
		Color(0.2, 1.0, 1.0, 0.55),
	]

	print("Chunk overlays: drawing %d dynamic entities" % entities.size())
	for i in range(entities.size()):
		var e: Dictionary = entities[i]
		var kind := String(e.get("kind", ""))
		var rec_type := String(e.get("record_type", ""))

		# Records without a decoded position get printed but not drawn.
		if not (e.has("source_x_px") and e.has("source_y_px")):
			print("  DE#%d type=%s kind=%s -- no decoded position (skipped)" % [i, rec_type, kind])
			continue

		var sx := int(e["source_x_px"])
		var sy := int(e["source_y_px"])
		var sw := int(e.get("width_px", tile_size))
		var sh := int(e.get("height_px", tile_size))

		var col: Color
		if kind == "chest":
			col = Color(1.0, 0.78, 0.1, 0.75)  # gold for treasure chests
		elif kind == "warp_alt":
			col = Color(0.6, 0.3, 1.0, 0.55)   # purple for alt warps
		elif kind.begins_with("warp_unknown"):
			col = Color(0.5, 0.5, 0.5, 0.55)
		else:
			col = palette[i % palette.size()]

		var rect := ColorRect.new()
		rect.size = Vector2(sw, sh)
		rect.position = Vector2(sx, sy)
		rect.color = col
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(rect)

		var label := Label.new()
		# Show the parser-assigned `record_id` (stable, matches the
		# blueprint JSON) rather than the loop index so labels can be
		# cross-referenced with the bin data. Fall back to the index
		# only when an entity has no record_id (synthetic recoveries).
		var rid_text := "rid=%d" % int(e["record_id"]) if e.has("record_id") else "#%d" % i
		var label_text := "[%s] %s type=%s\n  src=(%d,%d) %dx%d" % [
			kind.to_upper(), rid_text, rec_type, sx, sy, sw, sh
		]
		if e.has("target_lid"):
			label_text += "\n  -> lid=%d (%d,%d)" % [
				int(e["target_lid"]), int(e.get("target_x", 0)), int(e.get("target_y", 0))
			]
		label.text = label_text
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		label.position = Vector2(sx + sw + 2, sy - 4)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(label)

		print("  DE#%d kind=%s type=%s src=(%d,%d) %dx%d" % [
			i, kind, rec_type, sx, sy, sw, sh
		])


# ============================================================================
#  NPC SPRITES
# ============================================================================
# Spawns an AnimatedSprite2D for each scripted_entity in the chunk that
# carries a `sprite_id`. Always rendered (not gated by debug toggles).
# Sprites are placed top-left at (source_x_px, source_y_px) to match the
# existing placeholder anchoring, and parented under a single y-sorted
# container so they interleave with the player by screen-Y.
func _spawn_npcs(chunk_data: Dictionary) -> void:
	# Clean up any prior chunk's NPCs.
	for n in get_children():
		if n.name == "NpcSprites":
			remove_child(n)
			n.free()

	if not chunk_data.has("objects"):
		return
	var objects: Dictionary = chunk_data["objects"]
	var entities: Array = objects.get("dynamic_entities", [])
	if entities.is_empty():
		return

	# Pre-load dialogue tables for this town so the first click on any
	# NPC doesn't hitch on file IO. Safe no-op if already cached.
	if town_id != "":
		DialogueLoader.load_for_town(town_id)

	var container: Node2D = null
	var spawned: int = 0
	for e in entities:
		var kind := String(e.get("kind", ""))
		if kind != "scripted_entity" and kind != "shop_npc":
			continue
		if not (e.has("source_x_px") and e.has("source_y_px")):
			continue
		# The blueprint carries whichever id the record's identity slot held:
		# a texture id (sprite_id) or an npc instance id. NpcSpriteBuilder
		# resolves either to a spritesheet.
		var npc_id: int = int(e.get("sprite_id", e.get("npc_instance_id", 0)))
		if npc_id <= 0:
			continue

		var sprite := NpcSpriteBuilder.build(npc_id)
		if sprite == null:
			continue

		if container == null:
			container = Node2D.new()
			container.name = "NpcSprites"
			container.y_sort_enabled = true
			# Match the player's z so y-sorting interleaves them naturally.
			container.z_index = 5
			add_child(container)

		var pos := Vector2(int(e["source_x_px"]), int(e["source_y_px"]))
		if npc_sprite_scale != 1.0:
			sprite.scale = Vector2(npc_sprite_scale, npc_sprite_scale)
		# Build the clickable hit region. Sprite is parented to the
		# Area2D so they move/sort together, but the Area2D's position
		# is what determines pick-up coords. Sprite is `centered=false`
		# (top-left anchored) so the hit rectangle is offset to match.
		var interactable: Area2D = _make_npc_interactable(e, sprite)
		interactable.position = pos
		container.add_child(interactable)
		spawned += 1

	if spawned > 0:
		print("NPC sprites: spawned %d animated NPCs" % spawned)


# Wraps an NPC AnimatedSprite2D in an Area2D + RectangleShape2D for
# click-to-talk. Returns the Area2D (with the sprite already parented
# under it). `npc_interactable.gd` handles the input_event signal and
# popup spawning.
func _make_npc_interactable(entity: Dictionary, sprite: AnimatedSprite2D) -> Area2D:
	var script: Script = preload("res://features/town/npc_interactable.gd")
	var area: Area2D = script.new()
	area.dialogue_line_id = int(entity.get("dialogue_line_id", -1))
	area.town_id = town_id

	# Hit rectangle: prefer the blueprint's declared width/height, fall
	# back to the sprite's current animation frame size, then to a
	# single tile as a last resort.
	var w := int(entity.get("width_px", 0))
	var h := int(entity.get("height_px", 0))
	if w <= 0 or h <= 0:
		var frames := sprite.sprite_frames
		var anim_name := String(sprite.animation)
		if frames != null and frames.has_animation(anim_name) and frames.get_frame_count(anim_name) > 0:
			var tex: Texture2D = frames.get_frame_texture(anim_name, 0)
			if tex != null:
				if w <= 0: w = tex.get_width()
				if h <= 0: h = tex.get_height()
	if w <= 0: w = tile_size
	if h <= 0: h = tile_size
	# Account for the npc_sprite_scale applied to the sprite below.
	var sx: float = npc_sprite_scale if npc_sprite_scale != 1.0 else 1.0

	var shape := RectangleShape2D.new()
	shape.size = Vector2(w * sx, h * sx)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	# Sprite is centered=false (top-left); shift the rectangle so its
	# centre lands at top-left + (w/2, h/2).
	cs.position = Vector2((w * sx) * 0.5, (h * sx) * 0.5)
	area.add_child(cs)
	area.add_child(sprite)
	return area


# ============================================================================
# Spawns a clickable chest per `chest` entity in the chunk. The blueprint
# carries the two ids treasure_chest.gd needs (treasure_id -> field_treasure
# reward, open_switch_id -> looted state + sprite style); everything else is
# resolved from the database at spawn time. Chests recovered by the parser's
# tail-marker scan have no decoded position and are skipped.
func _spawn_chests(chunk_data: Dictionary) -> void:
	# Clean up any prior chunk's chests.
	for n in get_children():
		if n.name == "Chests":
			remove_child(n)
			n.free()

	if Engine.is_editor_hint() or not chunk_data.has("objects"):
		return
	var entities: Array = chunk_data["objects"].get("dynamic_entities", [])
	if entities.is_empty():
		return

	var chest_script: Script = preload("res://features/town/treasure_chest.gd")
	var container: Node2D = null
	var spawned: int = 0
	for e in entities:
		if String(e.get("kind", "")) != "chest":
			continue
		if not (e.has("source_x_px") and e.has("source_y_px")):
			continue

		if container == null:
			container = Node2D.new()
			container.name = "Chests"
			container.y_sort_enabled = true
			# Same z as NPCs and the player so y-sorting interleaves them.
			container.z_index = 5
			add_child(container)

		var chest: Area2D = chest_script.new()
		chest.setup(e)
		chest.position = Vector2(int(e["source_x_px"]), int(e["source_y_px"]))

		# Hit rectangle from the record's declared footprint (58x116 for a
		# standard chest: the sprite tile plus the tile you stand on).
		var w: int = int(e.get("width_px", 0))
		var h: int = int(e.get("height_px", 0))
		if w <= 0: w = tile_size
		if h <= 0: h = tile_size
		var shape := RectangleShape2D.new()
		shape.size = Vector2(w, h)
		var cs := CollisionShape2D.new()
		cs.shape = shape
		# Chest node is top-left anchored; centre the rectangle over it.
		cs.position = Vector2(w * 0.5, h * 0.5)
		chest.add_child(cs)

		container.add_child(chest)
		spawned += 1

	if spawned > 0:
		print("Treasure chests: spawned %d" % spawned)


# ============================================================================
#  WARP SYSTEM
# ============================================================================
# Cooldown prevents the destination warp from instantly re-firing right after
# we teleport the player onto it (which would ping-pong between two doorways).
var _last_warp_ms: int = -100000
const WARP_COOLDOWN_MS: int = 800


func _build_warp_triggers(chunk_data: Dictionary) -> void:
	# Spawns one Area2D per dynamic-entity warp record (type 0x0F). The
	# area covers the source rect from the blueprint (source_x_px/y_px +
	# width_px/height_px) and stores target_lid/target_x/target_y as meta
	# so _on_warp_area_entered can teleport the player.
	if not chunk_data.has("objects"):
		return
	var entities: Array = chunk_data["objects"].get("dynamic_entities", [])
	if entities.is_empty():
		return

	var container := Node2D.new()
	container.name = "WarpTriggers"
	add_child(container)

	var built := 0
	for e in entities:
		if String(e.get("record_type", "")) != "0x0F":
			continue
		var sub := int(e.get("sub_variant", -1))
		# Skip the misaligned chunk-18 garbage records (sub=0x00) which
		# decode to absurd target coordinates and would crash warp_to.
		if sub == 0x00:
			continue
		if not (e.has("source_x_px") and e.has("source_y_px")):
			continue
		var tlid := int(e.get("target_lid", -1))
		if tlid < 0:
			continue

		var sx := int(e["source_x_px"])
		var sy := int(e["source_y_px"])
		var sw := int(e.get("width_px", tile_size))
		var sh := int(e.get("height_px", tile_size))
		if sw <= 0: sw = tile_size
		if sh <= 0: sh = tile_size

		var area := Area2D.new()
		area.position = Vector2(sx, sy)
		# Monitor bodies (CharacterBody2D player), not areas.
		area.monitoring = true
		area.monitorable = false

		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(sw, sh)
		cs.shape = rs
		# Position shape so its top-left aligns with area.position.
		cs.position = Vector2(sw * 0.5, sh * 0.5)
		area.add_child(cs)

		area.set_meta("target_lid", tlid)
		area.set_meta("target_x", int(e.get("target_x", 0)))
		area.set_meta("target_y", int(e.get("target_y", 0)))
		area.set_meta("kind", String(e.get("kind", "")))
		area.body_entered.connect(_on_warp_area_entered.bind(area))

		container.add_child(area)
		built += 1

	print("Warp triggers: built %d Area2D doorways" % built)


func _on_warp_area_entered(body: Node, area: Area2D) -> void:
	if not body.is_in_group("player"):
		return
	if Time.get_ticks_msec() - _last_warp_ms < WARP_COOLDOWN_MS:
		return
	_last_warp_ms = Time.get_ticks_msec()
	var tlid := int(area.get_meta("target_lid"))
	var tx := int(area.get_meta("target_x"))
	var ty := int(area.get_meta("target_y"))
	# Defer so we don't free the firing Area2D from inside its own signal.
	call_deferred("warp_to", tlid, tx, ty)


# Resolves the target layer_id to a chunk index, redraws the destination
# chunk, then drops the player at (target_tile_x, target_tile_y) in tile
# space (centered on the destination tile).
func warp_to(target_lid: int, target_tile_x: int, target_tile_y: int) -> void:
	var idx := chunk_index_for_lid(target_lid)
	if idx < 0:
		push_warning("warp_to: layer_id %d not in this bin (external lid)" % target_lid)
		return

	print("--- WARP -> lid=%d (chunk %d) target_tile=(%d,%d) ---" % [
		target_lid, idx, target_tile_x, target_tile_y
	])

	# Setter on target_chunk triggers draw_chunk(idx) via trigger_redraw().
	# Force the redraw even when the value didn't change (e.g. re-warping
	# to the same chunk) by calling draw_chunk directly.
	if target_chunk != idx:
		target_chunk = idx
	else:
		draw_chunk(idx)

	# Reset cooldown so the destination doorway doesn't instantly fire on
	# the player's spawn position.
	_last_warp_ms = Time.get_ticks_msec()

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("warp_to: no node in group 'player' to reposition")
		return

	# Center the player on the destination tile.
	var px := target_tile_x * tile_size + int(tile_size * 0.5)
	var py := target_tile_y * tile_size + int(tile_size * 0.5)
	player.global_position = Vector2(px, py)
	# CharacterBody2D-specific: zero velocity so leftover motion doesn't
	# immediately drag the player back into a wall on the new map.
	if "velocity" in player:
		player.velocity = Vector2.ZERO
