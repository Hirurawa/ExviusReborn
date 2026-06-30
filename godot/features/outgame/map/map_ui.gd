extends Control

# World map driven by the WORLD/LAND/AREA/DUNGEON/TOWN/MISSION tables of the
# bundled SQLite datamine, queried on demand through the GameDatabase autoload.
# Three view levels share the same zoomable/pannable canvas:
#   * "world"   — shows the selected world's `dispOrder` background image with one
#     clickable ColorRect + name Label per land (LAND touchRect/labelPos).
#   * "area"    — entered by clicking a land; shows that land's areas as clickable
#     ColorRects + name Labels (AREA touchRect/labelPos). No background image
#     asset exists for this level, so the canvas is left blank.
#   * "dungeon" — entered by clicking an area; shows that area's detailed map
#     texture (assets/maps/map<areaId>.png) with one icon + name Label per dungeon
#     (DUNGEON position/iconFile) and per town (TOWN position/iconFile). If the
#     area map texture is missing the canvas is left blank but the dungeon/town
#     markers are still placed.
#
# The dungeon mission-list popup also reads the MISSION table just to list a
# dungeon's missions; the start/finish flow goes through MissionService, which
# also reads the MISSION + CHALLENGE tables via GameDatabase.

const WORLD_IMAGE_DIR: String = "res://assets/world/"
const AREA_MAP_DIR: String = "res://assets/maps/"
const REGION_MAP_DIR: String = "res://assets/maps/region/"
const MAP_ICON_DIR: String = "res://assets/map_icons/"
const MISSION_POPUP_SCENE: PackedScene = preload("res://features/outgame/map/DungeonMissionListPopup.tscn")

const DEFAULT_CANVAS_SIZE: Vector2 = Vector2(2000.0, 2000.0)
const AREA_CANVAS_FALLBACK: Vector2 = Vector2(640.0, 1136.0)
const DUNGEON_CANVAS_FALLBACK: Vector2 = Vector2(2000.0, 2000.0)
const DUNGEON_CANVAS_PADDING: float = 200.0

# Size assumed for a grid column/row whose tile file is missing, so the remaining
# tiles stay in their correct cells (FFBE map tiles are ~2048 px).
const AREA_MAP_TILE_FALLBACK_SIZE: float = 2048.0

const LAND_RECT_COLOR: Color = Color(0.3, 0.6, 1.0, 0.35)
const AREA_RECT_COLOR: Color = Color(1.0, 0.6, 0.3, 0.35)

@onready var map_scroll: ScrollContainer = $VBoxContainer/MapScrollContainer
@onready var map_sizer: Control = $VBoxContainer/MapScrollContainer/MapSizer
@onready var map_content: Control = $VBoxContainer/MapScrollContainer/MapSizer/MapContent
@onready var background_image: TextureRect = $VBoxContainer/MapScrollContainer/MapSizer/MapContent/BackgroundImage

@onready var map_world_option: OptionButton = $VBoxContainer/HBoxContainer/WorldOptionButton
@onready var map_world_row: Control = $VBoxContainer/HBoxContainer
@onready var map_top_bar: Control = $VBoxContainer/TopBar
@onready var map_back_button: TextureButton = $VBoxContainer/TopBar/UnitNamebgChara/BackButton

var map_zoom_level: float = 1.0
var _is_panning_map: bool = false

var current_view: String = "world" # "world" | "area" | "dungeon"
var current_selected_world: String = ""
var current_selected_land: String = ""
var current_selected_area: String = ""

var _texture_cache: Dictionary = {}
var _map_canvas_base_size: Vector2 = DEFAULT_CANVAS_SIZE

# Dungeon mission-list popup overlay (standalone scene, parented here so it stays
# above the zoomable map canvas) and a lazily-created error dialog.
var _mission_popup: DungeonMissionListPopup = null
var _mission_error_dialog: AcceptDialog = null

# Town-entry confirmation. `_pending_town_id` is the TOWN `townId`, handed to
# town_map_ui, which looks it up in the DB TOWN table (name + icon/folder).
var enter_town_dialog: ConfirmationDialog = null
var _pending_town_id: String = ""

func _ready() -> void:
	map_back_button.pressed.connect(_on_back_pressed)
	map_world_option.item_selected.connect(_on_map_world_selected)
	map_scroll.gui_input.connect(_on_map_scroll_gui_input)

	_populate_world_options()
	map_zoom_level = 1.0
	map_content.scale = Vector2(map_zoom_level, map_zoom_level)
	_apply_map_canvas_size(_map_canvas_base_size)
	_apply_default_view()


# === Default view ===

## Opens the map on the area of the player's most recent mission instead of the
## empty world picker, so returning players land where they left off. Uses the
## last-entered mission (falling back to the last cleared one), resolves its area
## via the MISSION table, and jumps straight to that area's dungeon view. Silently
## leaves the default "Select a World" state when there's no recent mission or its
## location can't be resolved.
func _apply_default_view() -> void:
	var mission_id: String = MissionService.last_entered_mission_id
	if mission_id == "":
		mission_id = MissionService.latest_cleared_mission_id
	if mission_id == "":
		return

	var location: Dictionary = GameDatabase.get_mission_location(mission_id)
	if location.is_empty():
		return

	var world_id: String = str(location.get("worldId", ""))
	var land_id: String = str(location.get("landId", ""))
	var area_id: String = str(location.get("areaId", ""))
	if world_id == "" or land_id == "" or area_id == "":
		return

	# Reflect the world in the dropdown, then open the area directly. Back
	# navigation still walks dungeon -> area -> world as usual.
	_select_world_option(world_id)
	_show_dungeon_view(world_id, land_id, area_id)

	# Pan so the originating dungeon sits in the middle of the viewport instead
	# of the default top-left corner.
	var dungeon_pos: Vector2 = _parse_pos(str(location.get("dungeonPosition", "")))
	if dungeon_pos != Vector2.ZERO:
		_center_view_on(dungeon_pos)


## Scrolls the map so canvas-space point `target` (map_content local coordinates)
## is centered in the viewport. Deferred one frame because the enclosing view was
## (re)built this same frame: the ScrollContainer only recomputes its scroll range
## on the next layout pass, so setting scroll any earlier clamps it back to zero.
func _center_view_on(target: Vector2) -> void:
	await get_tree().process_frame
	if not is_instance_valid(self) or current_view != "dungeon":
		return
	var viewport: Vector2 = map_scroll.size
	var scroll: Vector2 = target * map_zoom_level - viewport * 0.5
	map_scroll.scroll_horizontal = int(max(0.0, scroll.x))
	map_scroll.scroll_vertical = int(max(0.0, scroll.y))


## Selects the world dropdown entry whose metadata matches `world_id` (no-op if
## not present). Uses OptionButton.select(), which does not emit item_selected, so
## the caller drives the resulting view explicitly.
func _select_world_option(world_id: String) -> void:
	for i in range(map_world_option.item_count):
		if str(map_world_option.get_item_metadata(i)) == world_id:
			map_world_option.select(i)
			return


# === Coordinate parsing ===

func _parse_pos(raw: String) -> Vector2:
	# Format "x:y".
	var parts: PackedStringArray = raw.split(":")
	if parts.size() < 2:
		return Vector2.ZERO
	return Vector2(float(parts[0]), float(parts[1]))

func _parse_rect(raw: String) -> Rect2:
	# Format "x:y:w:h".
	var parts: PackedStringArray = raw.split(":")
	if parts.size() < 4:
		return Rect2()
	return Rect2(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))


# === Canvas / texture helpers ===

func _get_dynamic_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _apply_map_canvas_size(map_size: Vector2) -> void:
	_map_canvas_base_size = map_size
	map_content.size = map_size
	map_content.custom_minimum_size = map_size
	background_image.size = map_size
	map_sizer.custom_minimum_size = map_size * map_zoom_level

func _clear_overlays() -> void:
	for child in map_content.get_children():
		if child != background_image:
			child.queue_free()

func _reset_view_transform() -> void:
	map_zoom_level = 1.0
	map_content.scale = Vector2(map_zoom_level, map_zoom_level)
	map_sizer.custom_minimum_size = _map_canvas_base_size * map_zoom_level
	map_scroll.scroll_horizontal = 0
	map_scroll.scroll_vertical = 0


# === Input (zoom + pan) ===

func _on_map_scroll_gui_input(event: InputEvent) -> void:
	if _is_mission_popup_open():
		_is_panning_map = false
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_panning_map = event.pressed
		elif event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var old_zoom: float = map_zoom_level
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				map_zoom_level = clamp(map_zoom_level + 0.1, 0.5, 3.0)
			else:
				map_zoom_level = clamp(map_zoom_level - 0.1, 0.5, 3.0)

			if old_zoom != map_zoom_level:
				map_content.scale = Vector2(map_zoom_level, map_zoom_level)
				map_sizer.custom_minimum_size = _map_canvas_base_size * map_zoom_level
			map_scroll.accept_event()

	elif event is InputEventMouseMotion and _is_panning_map:
		map_scroll.scroll_horizontal -= int(event.relative.x)
		map_scroll.scroll_vertical -= int(event.relative.y)

# === World dropdown ===

func _populate_world_options() -> void:
	map_world_option.clear()
	_clear_overlays()

	map_world_option.add_item("Select a World", 0)
	map_world_option.set_item_metadata(0, "")

	var idx: int = 1
	for world in GameDatabase.get_worlds():
		var world_id: String = str(world.get("worldId", ""))
		if world_id == "":
			continue
		var world_name: String = str(world.get("worldName", "Unknown World"))
		map_world_option.add_item(world_name, idx)
		map_world_option.set_item_metadata(idx, world_id)
		idx += 1

func _on_map_world_selected(index: int) -> void:
	var world_id: String = str(map_world_option.get_item_metadata(index))
	if world_id == "":
		current_view = "world"
		current_selected_world = ""
		current_selected_land = ""
		current_selected_area = ""
		_clear_overlays()
		background_image.texture = null
		_apply_map_canvas_size(DEFAULT_CANVAS_SIZE)
		_reset_view_transform()
		return
	_show_world_view(world_id)


# === World view ===

func _show_world_view(world_id: String) -> void:
	current_view = "world"
	current_selected_world = world_id
	current_selected_land = ""
	current_selected_area = ""
	_clear_overlays()
	_close_mission_popup()

	var world: Dictionary = GameDatabase.get_world(world_id)
	var disp_order: String = str(world.get("dispOrder", ""))
	if disp_order != "":
		var tex: Texture2D = _get_dynamic_texture(WORLD_IMAGE_DIR + disp_order)
		if tex:
			background_image.texture = tex
			_apply_map_canvas_size(Vector2(tex.get_size()))
		else:
			background_image.texture = null
			_apply_map_canvas_size(DEFAULT_CANVAS_SIZE)
			push_warning("World map image missing: %s%s" % [WORLD_IMAGE_DIR, disp_order])
	else:
		background_image.texture = null
		_apply_map_canvas_size(DEFAULT_CANVAS_SIZE)

	for land in GameDatabase.get_lands(world_id):
		_add_region_marker(
			_parse_rect(str(land.get("touchRect", ""))),
			_parse_pos(str(land.get("labelPos", ""))),
			str(land.get("landName", "")),
			LAND_RECT_COLOR,
			_on_land_clicked.bind(world_id, str(land.get("landId", "")))
		)

	_reset_view_transform()

func _on_land_clicked(world_id: String, land_id: String) -> void:
	_show_area_view(world_id, land_id)


# === Area view ===

func _show_area_view(world_id: String, land_id: String) -> void:
	current_view = "area"
	current_selected_world = world_id
	current_selected_land = land_id
	current_selected_area = ""
	_clear_overlays()
	_close_mission_popup()

	var areas: Array = GameDatabase.get_areas(world_id, land_id)

	# Canvas must cover both the land's region-map background (LAND.mapFiles, a
	# single texture in assets/maps/region) and every area marker, since a few
	# lands have markers extending past the map image.
	var canvas: Vector2 = AREA_CANVAS_FALLBACK
	var land_map: String = GameDatabase.get_land_map(world_id, land_id)
	var tex: Texture2D = _get_dynamic_texture(REGION_MAP_DIR + land_map) if land_map != "" else null
	if tex:
		background_image.texture = tex
		canvas = canvas.max(Vector2(tex.get_size()))
	else:
		background_image.texture = null
	for area in areas:
		var rect: Rect2 = _parse_rect(str(area.get("touchRect", "")))
		canvas.x = max(canvas.x, rect.position.x + rect.size.x)
		canvas.y = max(canvas.y, rect.position.y + rect.size.y)
		var label_pos: Vector2 = _parse_pos(str(area.get("labelPos", "")))
		canvas.x = max(canvas.x, label_pos.x)
		canvas.y = max(canvas.y, label_pos.y)
	_apply_map_canvas_size(canvas)

	for area in areas:
		var area_id: String = str(area.get("areaId", ""))
		_add_region_marker(
			_parse_rect(str(area.get("touchRect", ""))),
			_parse_pos(str(area.get("labelPos", ""))),
			str(area.get("areaName", "")),
			AREA_RECT_COLOR,
			_on_area_clicked.bind(world_id, land_id, area_id)
		)

	_reset_view_transform()

func _on_area_clicked(world_id: String, land_id: String, area_id: String) -> void:
	_show_dungeon_view(world_id, land_id, area_id)


# === Area background tiles ===

## Builds the area's background as a grid of map tiles (AREA.mapFiles arranged by
## AREA.mapDimensions "cols:rows", row-major) added to map_content behind the
## markers. Returns the stitched canvas size, or Vector2.ZERO when the area has no
## mapFiles (the caller then falls back to the legacy single texture).
##
## Tiles aren't uniform but they tile cleanly — every tile in a column shares one
## width and every tile in a row shares one height — so summing the per-column
## widths and per-row heights reproduces the full map and keeps the dungeon/town
## marker coordinates aligned.
func _build_area_map_tiles(area_id: String) -> Vector2:
	var area_map: Dictionary = GameDatabase.get_area_map(area_id)
	var files: PackedStringArray = str(area_map.get("mapFiles", "")).split(",", false)
	if files.is_empty():
		return Vector2.ZERO

	var grid: Vector2i = _parse_map_dimensions(str(area_map.get("mapDimensions", "")), files.size())
	var cols: int = grid.x
	var rows: int = grid.y
	var cell_count: int = min(files.size(), cols * rows)

	# Load tiles and measure per-column widths / per-row heights.
	var textures: Array = []
	textures.resize(cell_count)
	var col_w: PackedFloat32Array = PackedFloat32Array()
	col_w.resize(cols)
	var row_h: PackedFloat32Array = PackedFloat32Array()
	row_h.resize(rows)
	for i in range(cell_count):
		var tex: Texture2D = _get_dynamic_texture(AREA_MAP_DIR + str(files[i]).strip_edges())
		textures[i] = tex
		if tex:
			var size: Vector2 = Vector2(tex.get_size())
			col_w[i % cols] = max(col_w[i % cols], size.x)
			row_h[i / cols] = max(row_h[i / cols], size.y)

	# Columns/rows whose tiles are all missing still need a size so the tiles that
	# do exist stay in their correct grid cells.
	for c in range(cols):
		if col_w[c] <= 0.0:
			col_w[c] = AREA_MAP_TILE_FALLBACK_SIZE
	for r in range(rows):
		if row_h[r] <= 0.0:
			row_h[r] = AREA_MAP_TILE_FALLBACK_SIZE

	# Cumulative pixel offset of each column/row.
	var x_off: PackedFloat32Array = PackedFloat32Array()
	x_off.resize(cols)
	var total_w: float = 0.0
	for c in range(cols):
		x_off[c] = total_w
		total_w += col_w[c]
	var y_off: PackedFloat32Array = PackedFloat32Array()
	y_off.resize(rows)
	var total_h: float = 0.0
	for r in range(rows):
		y_off[r] = total_h
		total_h += row_h[r]

	# Place each tile (missing ones are skipped; their cells stay reserved above).
	for i in range(cell_count):
		var tex2: Texture2D = textures[i]
		if tex2 == null:
			continue
		var tile: TextureRect = TextureRect.new()
		tile.texture = tex2
		tile.position = Vector2(x_off[i % cols], y_off[i / cols])
		tile.size = Vector2(tex2.get_size())
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_content.add_child(tile)

	return Vector2(total_w, total_h)


## Parses AREA.mapDimensions ("cols:rows") into a Vector2i grid. Falls back to a
## single row of `file_count` tiles when the value is missing/invalid, and trims
## the row count so the grid never has more cells than files (a few areas declare
## more cells than they actually list files for).
func _parse_map_dimensions(raw: String, file_count: int) -> Vector2i:
	var parts: PackedStringArray = raw.split(":")
	var cols: int = int(parts[0]) if parts.size() >= 1 and str(parts[0]).is_valid_int() else 0
	var rows: int = int(parts[1]) if parts.size() >= 2 and str(parts[1]).is_valid_int() else 0
	if cols <= 0 or rows <= 0:
		return Vector2i(maxi(file_count, 1), 1)
	if cols * rows > file_count:
		rows = maxi(int(ceil(float(file_count) / float(cols))), 1)
	return Vector2i(cols, rows)


# === Dungeon view ===

func _show_dungeon_view(world_id: String, land_id: String, area_id: String) -> void:
	current_view = "dungeon"
	current_selected_world = world_id
	current_selected_land = land_id
	current_selected_area = area_id
	_clear_overlays()
	_close_mission_popup()

	var dungeons: Array = GameDatabase.get_dungeons(area_id)
	var towns: Array = GameDatabase.get_towns(area_id)

	# Background: the area's map is a grid of tile textures (AREA.mapFiles arranged
	# per AREA.mapDimensions). Falls back to the legacy single map<areaId>.png, then
	# to a blank canvas sized to fit the dungeon/town markers.
	background_image.texture = null
	var tiled_size: Vector2 = _build_area_map_tiles(area_id)
	if tiled_size != Vector2.ZERO:
		_apply_map_canvas_size(tiled_size)
	else:
		var tex: Texture2D = _get_dynamic_texture("%smap%s.png" % [AREA_MAP_DIR, area_id])
		if tex:
			background_image.texture = tex
			_apply_map_canvas_size(Vector2(tex.get_size()))
		else:
			var canvas: Vector2 = DUNGEON_CANVAS_FALLBACK
			for dungeon in dungeons:
				var pos: Vector2 = _parse_pos(str(dungeon.get("position", "")))
				canvas.x = max(canvas.x, pos.x + DUNGEON_CANVAS_PADDING)
				canvas.y = max(canvas.y, pos.y + DUNGEON_CANVAS_PADDING)
			for town in towns:
				var town_pos: Vector2 = _parse_pos(str(town.get("position", "")))
				canvas.x = max(canvas.x, town_pos.x + DUNGEON_CANVAS_PADDING)
				canvas.y = max(canvas.y, town_pos.y + DUNGEON_CANVAS_PADDING)
			_apply_map_canvas_size(canvas)

	for town in towns:
		var town_id: String = str(town.get("townId", ""))
		var town_name: String = str(town.get("townName", ""))
		_add_point_marker(
			_parse_pos(str(town.get("position", ""))),
			MAP_ICON_DIR + str(town.get("iconFile", "")),
			town_name,
			_on_town_clicked.bind(town_id, town_name)
		)

	for dungeon in dungeons:
		var dungeon_id: String = str(dungeon.get("dungeonId", ""))
		var dungeon_name: String = str(dungeon.get("name", ""))
		_add_point_marker(
			_parse_pos(str(dungeon.get("position", ""))),
			MAP_ICON_DIR + str(dungeon.get("iconFile", "")),
			dungeon_name,
			_on_dungeon_clicked.bind(dungeon_id, dungeon_name)
		)

	_reset_view_transform()


# === Shared marker builder ===

func _add_region_marker(rect: Rect2, label_pos: Vector2, marker_name: String, color: Color, on_click: Callable) -> void:
	var color_rect: ColorRect = ColorRect.new()
	color_rect.color = color
	color_rect.position = rect.position
	color_rect.size = rect.size
	if on_click.is_valid():
		# PASS (not STOP) so wheel-zoom and drag-pan still reach the scroll
		# container when the cursor is over a large land/area rect. We only treat
		# a press+release that barely moved as a "tap" to drill in, leaving drags
		# free to pan.
		color_rect.mouse_filter = Control.MOUSE_FILTER_PASS
		var tap_state: Dictionary = {"press_pos": Vector2.ZERO}
		color_rect.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					tap_state["press_pos"] = event.global_position
				elif event.global_position.distance_to(tap_state["press_pos"]) <= 8.0:
					on_click.call()
		)
	else:
		color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_content.add_child(color_rect)

	var lbl: Label = Label.new()
	lbl.text = marker_name
	lbl.position = label_pos
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	map_content.add_child(lbl)


# Point-based marker for dungeons and towns (image centered on `position`, name
# below). When `on_click` is valid the icon becomes tappable; towns pass no
# callable and stay non-interactive.
func _add_point_marker(position: Vector2, icon_path: String, marker_name: String, on_click: Callable = Callable()) -> void:
	var icon_size: Vector2 = Vector2.ZERO
	var tex: Texture2D = _get_dynamic_texture(icon_path)
	if tex:
		var icon: TextureRect = TextureRect.new()
		icon.texture = tex
		icon_size = Vector2(tex.get_size())
		icon.position = position - icon_size * 0.5
		if on_click.is_valid():
			# PASS (not STOP) so wheel-zoom and drag-pan still reach the scroll
			# container; only a press+release that barely moved counts as a tap.
			icon.mouse_filter = Control.MOUSE_FILTER_PASS
			var tap_state: Dictionary = {"press_pos": Vector2.ZERO}
			icon.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
					if event.pressed:
						tap_state["press_pos"] = event.global_position
					elif event.global_position.distance_to(tap_state["press_pos"]) <= 8.0:
						on_click.call()
			)
		else:
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_content.add_child(icon)

	var lbl: Label = Label.new()
	lbl.text = marker_name
	lbl.custom_minimum_size = Vector2(200.0, 0.0)
	lbl.position = Vector2(position.x - 100.0, position.y + icon_size.y * 0.5)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	map_content.add_child(lbl)


# === Navigation ===

func _on_back_pressed() -> void:
	if _is_mission_popup_open():
		_close_mission_popup()
		return
	if current_view == "dungeon":
		_show_area_view(current_selected_world, current_selected_land)
		return
	if current_view == "area":
		_show_world_view(current_selected_world)
		return
	UIManager.pop()


# === Dungeon mission-list popup ===

func _on_dungeon_clicked(dungeon_id: String, dungeon_name: String) -> void:
	var raw_missions: Array = []
	for mission in GameDatabase.get_missions(dungeon_id):
		if _is_mission_popup_available(mission):
			raw_missions.append(mission)
	var missions: Array[Dictionary] = _build_mission_popup_entries(raw_missions)
	_open_mission_popup(dungeon_name, missions)


func _open_mission_popup(dungeon_name: String, missions: Array[Dictionary]) -> void:
	_close_mission_popup()

	var popup: DungeonMissionListPopup = MISSION_POPUP_SCENE.instantiate() as DungeonMissionListPopup
	if popup == null:
		return

	add_child(popup)
	_mission_popup = popup
	_set_map_top_bar_visible(false)

	popup.init_scene({
		"dungeon_name": dungeon_name,
		"missions": missions,
	})
	popup.mission_selected.connect(_on_mission_row_pressed)
	popup.home_pressed.connect(_on_mission_popup_home_pressed)
	popup.back_pressed.connect(_on_back_pressed)


func _build_mission_popup_entries(missions: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for mission_value in missions:
		if not (mission_value is Dictionary):
			continue
		var mission: Dictionary = (mission_value as Dictionary).duplicate(true)
		var mission_id: String = str(mission.get("missionId", ""))
		if mission_id == "":
			continue
		mission["difficulty"] = GameDatabase.get_mission_difficulty(mission_id)
		mission["row_state"] = _resolve_mission_row_state(mission_id)
		mission["challenges"] = GameDatabase.get_mission_challenges(mission_id)
		var progress: Variant = MissionService.cleared_missions.get(mission_id, {})
		if progress is Dictionary and (progress as Dictionary).has("objectives"):
			mission["objectives"] = (progress as Dictionary).get("objectives", [])
		entries.append(mission)
	return entries


func _resolve_mission_row_state(mission_id: String) -> String:
	var progress: Variant = MissionService.cleared_missions.get(mission_id, {})
	if progress is Dictionary and bool((progress as Dictionary).get("cleared", false)):
		return "clear"
	if mission_id == MissionService.last_entered_mission_id:
		return "achieving"
	return "default"


func _is_mission_popup_available(mission: Dictionary) -> bool:
	var switch_service: Node = get_node_or_null("/root/SwitchService")
	if switch_service != null and switch_service.has_method("is_unlocked"):
		return bool(switch_service.call("is_unlocked", mission.get("switchInfo")))
	return true


func _close_mission_popup() -> void:
	if _mission_popup != null and is_instance_valid(_mission_popup):
		_mission_popup.queue_free()
	_mission_popup = null
	_set_map_top_bar_visible(true)


func _on_mission_row_pressed(mission_id: String) -> void:
	_close_mission_popup()
	# Start flow goes through MissionService (mission data from the DB). Missions
	# with no encounter data return success=false and surface a friendly error.
	var result: Dictionary = await MissionService.request_start_mission(mission_id)
	if result.get("success", false) == true:
		UIManager.push("combat_ui", {"mission_id": mission_id})
	else:
		_show_mission_error(str(result.get("error", "Could not start this mission.")))


func _on_mission_popup_home_pressed() -> void:
	_close_mission_popup()
	UIManager.set_root("game_ui")


func _is_mission_popup_open() -> bool:
	return _mission_popup != null and is_instance_valid(_mission_popup)


func _set_map_top_bar_visible(show_bar: bool) -> void:
	if map_top_bar != null:
		map_top_bar.visible = show_bar
	if map_world_row != null:
		map_world_row.visible = show_bar


func _show_mission_error(message: String) -> void:
	if _mission_error_dialog == null or not is_instance_valid(_mission_error_dialog):
		_mission_error_dialog = AcceptDialog.new()
		_mission_error_dialog.title = "Cannot Start Mission"
		add_child(_mission_error_dialog)
	_mission_error_dialog.dialog_text = message
	_mission_error_dialog.popup_centered()


# === Town entry ===

func _on_town_clicked(town_id: String, town_name: String) -> void:
	_pending_town_id = town_id
	if enter_town_dialog == null or not is_instance_valid(enter_town_dialog):
		enter_town_dialog = ConfirmationDialog.new()
		enter_town_dialog.title = "Enter Town"
		enter_town_dialog.ok_button_text = "Yes"
		enter_town_dialog.cancel_button_text = "No"
		enter_town_dialog.confirmed.connect(_on_enter_town_confirmed)
		add_child(enter_town_dialog)
	var display_name: String = town_name if town_name != "" else "this town"
	enter_town_dialog.dialog_text = "Enter %s?" % display_name
	enter_town_dialog.popup_centered()


func _on_enter_town_confirmed() -> void:
	if _pending_town_id == "":
		return
	UIManager.push("town_map_ui", {"town_id": _pending_town_id})
