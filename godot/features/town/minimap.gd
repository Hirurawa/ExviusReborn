extends CanvasLayer
class_name Minimap

# Walkable / wall colors used when baking the collision image.
@export var walkable_color: Color = Color(0.85, 0.85, 0.90, 0.85)
@export var wall_color: Color = Color(0.10, 0.10, 0.15, 0.95)
@export var background_color: Color = Color(0.0, 0.0, 0.0, 0.55)
@export var player_color: Color = Color(1.0, 0.85, 0.20, 1.0)
@export var npc_color: Color = Color(0.30, 1.00, 0.45, 1.0)        # green for NPCs
@export var warp_color: Color = Color(0.30, 0.75, 1.00, 1.0)       # cyan-blue
@export var warp_alt_color: Color = Color(0.65, 0.35, 1.00, 1.0)   # purple
@export var chest_color: Color = Color(1.00, 0.55, 0.05, 1.0)      # orange-gold
@export var entity_color: Color = Color(1.00, 0.30, 0.30, 1.0)     # red for unknown
@export var frame_size: Vector2 = Vector2(220, 220)
@export var frame_margin: Vector2 = Vector2(16, 16)
# How many minimap pixels each tile is drawn at. Larger = zoomed in.
@export var zoom_tile_size: int = 12
# Pixel size of the player marker, in minimap pixels.
@export var player_marker_size: float = 7.0
# Default pixel size of category markers (warps, chests, ...).
@export var marker_size: float = 5.0
# When true, the map stops scrolling at its edges so the player walks
# off-center near borders instead of revealing empty space.
@export var clamp_to_edges: bool = true

var _frame: Panel        # outer panel with border + clipping
var _viewport: Control   # inner clipped container (same size as frame interior)
var _map: TextureRect    # baked collision texture, scrolled to follow player
var _markers: Control    # holds category markers; child of _map so it scrolls
var _player_marker: ColorRect

# Pixel dimensions of the most recent baked image (= chunk grid size).
var _grid_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	add_to_group("minimap")
	# Sit above the main 2D layer; ChunkOverlays use z=1000 / 2000 in
	# world-space but a CanvasLayer renders independently of z.
	layer = 100

	_frame = Panel.new()
	_frame.name = "Frame"
	_frame.size = frame_size
	_frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_frame.position = Vector2(frame_margin.x, frame_margin.y)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Plain dark backdrop with a thin border.
	var sb := StyleBoxFlat.new()
	sb.bg_color = background_color
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	_frame.add_theme_stylebox_override("panel", sb)
	add_child(_frame)

	# The viewport is the clipped window the player sees through. The
	# map TextureRect is sized to the full chunk and scrolled inside.
	_viewport = Control.new()
	_viewport.name = "Viewport"
	_viewport.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.offset_left = 4
	_viewport.offset_top = 4
	_viewport.offset_right = -4
	_viewport.offset_bottom = -4
	_viewport.clip_contents = true
	_viewport.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_viewport)

	_map = TextureRect.new()
	_map.name = "Map"
	# Size is set when a chunk is baked: grid_size * zoom_tile_size.
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_map)

	# Category markers (warps, chests, ...) are placed as children of the
	# map so they automatically scroll and zoom with it. Their pixel
	# position inside _map is grid_pos * zoom_tile_size.
	_markers = Control.new()
	_markers.name = "Markers"
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.add_child(_markers)

	# Player marker. Lives in viewport space; positioned by
	# set_player_grid_pos() to stay aligned with the player's actual
	# location even when the map clamps near edges.
	_player_marker = ColorRect.new()
	_player_marker.name = "PlayerMarker"
	_player_marker.color = player_color
	_player_marker.size = Vector2(player_marker_size, player_marker_size)
	_player_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_marker.visible = false
	_viewport.add_child(_player_marker)


# Bake a (grid_w x grid_h) image with walkable / blocked colors and
# install it as the minimap texture. `blocked_cells` is the list of
# walls (in tile coordinates) from TileMap.debug_cells_collision.
func set_walkable_map(grid_w: int, grid_h: int, blocked_cells: Array) -> void:
	if grid_w <= 0 or grid_h <= 0:
		return
	_grid_size = Vector2i(grid_w, grid_h)
	var img := Image.create(grid_w, grid_h, false, Image.FORMAT_RGBA8)
	img.fill(walkable_color)
	for cell in blocked_cells:
		var v: Vector2i = cell
		if v.x >= 0 and v.y >= 0 and v.x < grid_w and v.y < grid_h:
			img.set_pixel(v.x, v.y, wall_color)
	_map.texture = ImageTexture.create_from_image(img)
	# Draw the texture at zoom_tile_size pixels per tile.
	_map.size = Vector2(grid_w, grid_h) * float(zoom_tile_size)
	_player_marker.visible = true
	# Existing markers are tied to the previous chunk's coordinate space.
	for c in _markers.get_children():
		c.queue_free()


# Scroll the map so the given player grid position is at the viewport
# center (clamped to map edges when `clamp_to_edges` is true).
func set_player_grid_pos(grid_pos: Vector2) -> void:
	if _grid_size.x <= 0 or _grid_size.y <= 0 or _map.texture == null:
		return
	var view_size: Vector2 = _viewport.size
	var view_center: Vector2 = view_size * 0.5
	var player_px: Vector2 = grid_pos * float(zoom_tile_size)
	# Position the map so player_px lands at view_center.
	var pos: Vector2 = view_center - player_px
	if clamp_to_edges:
		# When the map is smaller than the viewport along an axis, keep
		# it centered on that axis. Otherwise clamp so its edges never
		# pull inside the viewport interior.
		if _map.size.x <= view_size.x:
			pos.x = (view_size.x - _map.size.x) * 0.5
		else:
			pos.x = clamp(pos.x, view_size.x - _map.size.x, 0.0)
		if _map.size.y <= view_size.y:
			pos.y = (view_size.y - _map.size.y) * 0.5
		else:
			pos.y = clamp(pos.y, view_size.y - _map.size.y, 0.0)
	_map.position = pos
	# Marker tracks the player's actual grid location, which may differ
	# from view_center when clamping pushes the map off-center near
	# borders.
	_player_marker.position = (player_px + _map.position) - _player_marker.size * 0.5


# Hide the marker (e.g. when no chunk is active yet).
func clear_player() -> void:
	_player_marker.visible = false


# Replace the set of category markers (warps, chests, ...). Each entry
# is a Dictionary with keys:
#   grid_pos : Vector2   -- center of the marker, in tile coordinates
#   color    : Color
#   size     : float     -- optional pixel size (defaults to marker_size)
func set_markers(entries: Array) -> void:
	for c in _markers.get_children():
		c.queue_free()
	for entry in entries:
		var e: Dictionary = entry
		var gp: Vector2 = e.get("grid_pos", Vector2.ZERO)
		var col: Color = e.get("color", entity_color)
		var sz: float = float(e.get("size", marker_size))
		var dot := ColorRect.new()
		dot.size = Vector2(sz, sz)
		dot.color = col
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Position in _map space; markers scroll with the map.
		dot.position = gp * float(zoom_tile_size) - Vector2(sz, sz) * 0.5
		_markers.add_child(dot)


# Helper exposing the configured category colors so callers (tile_map)
# don't have to hard-code the palette themselves.
func color_for_kind(kind: String) -> Color:
	match kind:
		"scripted_entity":
			return npc_color
		"warp":
			return warp_color
		"warp_alt":
			return warp_alt_color
		"chest":
			return chest_color
		_:
			if kind.begins_with("warp"):
				return warp_color
			return entity_color
