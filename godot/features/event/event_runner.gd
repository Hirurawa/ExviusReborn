extends Node2D
class_name EventRunner

# Plays back a decoded FFBE cutscene from an event_blueprint.json file.
#
# Folder convention: an event id `XXXXXXXY1+` runs on map id `XXXXXXXY0`
# (e.g. event 112020301 plays on map 112020300). We try to load the
# matching town into the sibling TileMap; if the town isn't present
# under res://assets/town_data, we still spawn actors and run the
# script -- you just won't see the floor tiles.
#
# Cutscene semantics:
#   - Each opcode dispatch returns immediately. Animated commands
#     (move_actor with ticks > 0, camera_scroll with ticks > 0) start
#     a Tween and let the script keep ticking.
#   - `advance` is a *sync point*: it waits for all in-flight actor
#     tweens to settle, and (if a dialog line is on screen) waits for
#     the player to press Space / Enter to dismiss it.
#   - `short_wait` is a plain timer.
#   - Unknown opcodes are no-ops but logged.

const EVENT_ASSET_ROOT := "res://assets/town_data/"
const FALLBACK_TILE_SIZE := 58       # matches tile_map.gd default
const FRAMES_PER_SECOND := 60.0
const TILE_SIZE := 58.0

@export var event_id: String = ""
@export var auto_start: bool = true
# Which dialog block to play. 0 = first scene (most events). Some
# event.bin files contain multiple back-to-back scenes plus a few
# false-positive resync blocks; advance through legitimate ones by
# bumping this in the inspector and re-running.
@export var block_index: int = 0
# When true, only the block at block_index is played and the runner
# stops. When false, all blocks play in sequence (legacy behaviour --
# usually plays through garbage blocks too).
@export var single_block: bool = true
@export_node_path("TileMap") var tile_map_path: NodePath
@export_node_path("Camera2D") var camera_path: NodePath
@export_node_path("Label") var dialog_label_path: NodePath

# Map of actor_id -> EventActor instance.
var _actors: Dictionary = {}
# Toggled by op_0x67 (set_move_mode). When true, subsequent move_actor
# calls render at run speed (`ticks` is treated as total frames rather
# than frames-per-tile, which is how the engine renders the run-sprite
# bursts at @0x34c9+ in 112020101).
# Set true while a text line is shown; `advance` blocks until cleared.
var _awaiting_dialog: bool = false
# Cached references resolved in _ready().
var _tile_map: Node = null
var _camera: Camera2D = null
var _dialog_label: Label = null
# Loaded `<event_id>_event_text.txt` (text_id -> raw line).
var _text_strings: Dictionary = {}
# Currently running tweens we need to wait on at the next `advance`.
var _pending_tweens: Array[Tween] = []
# Toggled by op_0x67 (set_move_mode). See declaration note above _actors.
var _run_mode: bool = false

func _ready() -> void:
	_tile_map = get_node_or_null(tile_map_path)
	_camera = get_node_or_null(camera_path)
	_dialog_label = get_node_or_null(dialog_label_path)
	_set_dialog_visible(false)
	if auto_start and event_id != "":
		# Defer one frame so the sibling TileMap finishes its own
		# _ready (and the tileset is in place before we drop sprites).
		call_deferred("run_event", event_id)

func _unhandled_input(event: InputEvent) -> void:
	if not _awaiting_dialog:
		return
	# Only keyboard advances dialog -- mouse is reserved for camera
	# pan / zoom (camera_2d.gd handles drag + scroll) so the user can
	# inspect the stage without inadvertently skipping a line.
	if event.is_action_pressed("ui_accept"):
		_awaiting_dialog = false
		_set_dialog_visible(false)

# Public entry point. Loads the blueprint, asks the TileMap to draw
# the matching town (if available), spawns actors from the setup
# commands and walks the dialog blocks.
func run_event(eid: String) -> void:
	event_id = eid
	var bp := _load_blueprint(eid)
	if bp.is_empty():
		push_warning("EventRunner: no blueprint for %s" % eid)
		return
	_text_strings = _load_text_strings(eid)

	# Try to load the parent map (XXXXXXXY0).
	if _tile_map != null and eid.length() >= 1:
		var map_id := eid.substr(0, eid.length() - 2) + "00" 
		var map_dir := "res://assets/town_data/" + map_id
		if DirAccess.dir_exists_absolute(map_dir):
			_tile_map.call("load_town", map_id)
			# load_town() warps to the map's bin-header default layer.
			# Per-event scenes on the same map sometimes take place on
			# a different layer (e.g. 111010101 needs layer 65 instead
			# of 111010100's initial_layer_id=61). The bin doesn't
			# encode the layer directly anywhere we've decoded yet, so
			# we infer it from the first PC spawn: pick the smallest
			# layer whose pixel bounds contain that spawn. The default
			# layer wins ties when its bounds also fit.
			_resolve_event_layer(map_dir, bp)
		else:
			push_warning("EventRunner: town_data/%s not found; running without floor tiles" % map_id)

	# Clear any previous actors.
	for child in get_children():
		if child is EventActor:
			child.queue_free()
	_actors.clear()
	_run_mode = false

	await _execute_commands(bp.get("pre_script", {}).get("setup_commands", []))

	# Setup is responsible for placing the camera (via op_0x3a's
	# camera_position + any camera_scroll calls). We no longer
	# snap the camera to actor 1 after setup -- doing so was
	# overwriting the result of the cinematic establishing pan.

	# Walk dialog block(s). When single_block is true, only play the
	# user-selected block_index -- otherwise iterate every block.
	var blocks: Array = bp.get("script", {}).get("blocks", [])
	if single_block:
		if block_index >= 0 and block_index < blocks.size():
			await _execute_commands(blocks[block_index].get("commands", []))
	else:
		for blk in blocks:
			await _execute_commands(blk.get("commands", []))

	print("EventRunner: event %s finished." % eid)

func _resolve_event_layer(map_dir: String, bp: Dictionary) -> void:
	# Find the first PC spawn (actor_id=1, absolute move) in setup.
	var spawn := Vector2i(-1, -1)
	for c_any in bp.get("pre_script", {}).get("setup_commands", []):
		var c: Dictionary = c_any
		if c.get("name", "") == "move_actor" and c.get("mode", "") == "absolute" and int(c.get("actor_id", 0)) == 1:
			spawn = Vector2i(int(c.get("x", 0)), int(c.get("y", 0)))
			break
	if spawn.x < 0:
		return
	# Read the map blueprint to enumerate layer bounds + the default.
	var bp_path := map_dir + "/map_blueprint.json"
	if not FileAccess.file_exists(bp_path):
		return
	var f := FileAccess.open(bp_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var mp: Dictionary = parsed
	var default_lid := int(mp.get("initial_layer_id", -1))
	var tile_px := int(TILE_SIZE)
	# Does the default layer already contain the spawn? If so, leave
	# tile_map's existing warp_to() alone.
	var layers: Array = mp.get("layers", [])
	for L_any in layers:
		var L: Dictionary = L_any
		if int(L.get("layer_id", -1)) != default_lid:
			continue
		var w := int(L.get("grid_width", 0)) * tile_px
		var h := int(L.get("grid_height", 0)) * tile_px
		if spawn.x < w and spawn.y < h:
			return
		break
	# Otherwise pick the smallest layer whose bounds contain the spawn.
	var best_lid := -1
	var best_area := -1
	for L_any in layers:
		var L: Dictionary = L_any
		var lid := int(L.get("layer_id", -1))
		var w := int(L.get("grid_width", 0)) * tile_px
		var h := int(L.get("grid_height", 0)) * tile_px
		if w <= 0 or h <= 0:
			continue
		if spawn.x >= w or spawn.y >= h:
			continue
		var area := w * h
		if best_lid < 0 or area < best_area:
			best_lid = lid
			best_area = area
	if best_lid < 0 or best_lid == default_lid:
		return
	var tx := spawn.x / tile_px
	var ty := spawn.y / tile_px
	print("EventRunner: spawn (%d,%d) doesn't fit default lid=%d; warping to lid=%d" % [spawn.x, spawn.y, default_lid, best_lid])
	_tile_map.call("warp_to", best_lid, tx, ty)

func _load_blueprint(eid: String) -> Dictionary:
	var path := "%s/%s/event_blueprint.json" % [EVENT_ASSET_ROOT, eid]
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _load_text_strings(eid: String) -> Dictionary:
	var path := "%s/%s/%s_event_text.txt" % [EVENT_ASSET_ROOT, eid, eid]
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	for line in f.get_as_text().split("\n"):
		var comma := line.find(",")
		if comma <= 0:
			continue
		var key_s := line.substr(0, comma)
		var val := line.substr(comma + 1)
		if key_s.is_valid_int():
			out[int(key_s)] = val
	return out

# --------------------------------------------------------------- core
# Iterate a list of decoded opcodes, dispatching each. `advance` acts
# as the sync barrier that flushes pending tweens + dialog wait.
func _execute_commands(commands: Array) -> void:
	for c_any in commands:
		var c: Dictionary = c_any
		_log_command(c)
		match c.get("name", ""):
			"advance":
				await _flush_sync_point()
			"short_wait":
				var ticks: int = int(c.get("ticks", 0))
				if ticks > 0:
					await get_tree().create_timer(ticks / FRAMES_PER_SECOND).timeout
			"text":
				_handle_text(c)
			"move_actor":
				_handle_move_actor(c)
			"face_actor":
				_handle_face_actor(c)
			"set_actor_visible":
				_handle_visibility(c)
			"camera_scroll":
				_handle_camera_scroll(c)
			"show_bubble":
				_handle_show_bubble(c)
			"play_vfx":
				print("[event] play_vfx %s" % c.get("filename", "?"))
			"scene_config":
				# op_0x3a is a container -- its embedded_moves field
				# carries the initial actor placements (absolute coords).
				# Apply them synchronously so the party is positioned
				# before any subsequent relative dy/dx moves run.
				_handle_scene_config(c)
			"set_move_mode":
				_run_mode = String(c.get("mode", "walk")) == "run"
				print("  (run_mode=%s)" % _run_mode)
			_:
				# Unknown / unhandled opcode -- log once for triage.
				pass

# Wait for in-flight tweens and (if any) the on-screen dialog line.
func _flush_sync_point() -> void:
	for t in _pending_tweens:
		if t != null and t.is_valid() and t.is_running():
			await t.finished
	_pending_tweens.clear()
	# Spin until the user dismisses the current dialog line.
	while _awaiting_dialog:
		await get_tree().process_frame

# Print a one-line trace for the command we're about to dispatch.
# Format matches the address shown in ImHex when you open the .bin with
# imhex_event.hexpat, so a complaint of "at @0x5f0f the move was wrong"
# maps directly to a byte the parser already named.
func _log_command(c: Dictionary) -> void:
	var off: int = int(c.get("offset", -1))
	var name: String = c.get("name", "?")
	var extras: Array[String] = []
	for k in ["actor_id", "variant", "direction_name", "visible",
		"mode", "x", "y", "dx", "dy", "ticks",
		"text_id", "bubble_name", "duration",
		"filename", "flag"]:
		if c.has(k):
			extras.append("%s=%s" % [k, str(c[k])])
	var addr := "????" if off < 0 else "@0x%04x" % off
	var preview: String = c.get("text_preview", "")
	if preview != "":
		extras.append('"%s"' % preview.replace("\n", " / "))
	print("[ev %s %s %s %s]" % [event_id, addr, name, " ".join(extras)])

# ------------------------------------------------------------- handlers
func _get_or_spawn_actor(actor_id: int, is_npc: bool) -> EventActor:
	if _actors.has(actor_id):
		return _actors[actor_id]
	var a := EventActor.new()
	a.actor_id = actor_id
	a.is_npc = is_npc
	a.name = "Actor_%d" % actor_id
	add_child(a)
	_actors[actor_id] = a
	return a

func _handle_move_actor(c: Dictionary) -> void:
	var aid: int = int(c.get("actor_id", 0))
	var is_npc: bool = int(c.get("variant", 0)) == 1
	var actor := _get_or_spawn_actor(aid, is_npc)
	var mode: String = c.get("mode", "absolute")
	var ticks: int = int(c.get("ticks", 0))
	# The 3-byte trailer at the end of a move_actor payload encodes
	# some kind of motion flags, but the meaning is not yet pinned
	# down. Survey across all parsed events shows the most common
	# trailers are 01 01 00 (~9k), 00 00 00 (~7.5k), 01 01 01 (~1.2k)
	# and 01 00 00 (~0.9k). An earlier heuristic gated translations on
	# trailer == 01 01 01 -- that turned out to be the rare case and
	# was suppressing legitimate walks (e.g. Rain's two downward moves
	# at 0x1ebe / 0x1edc in 111010105). For now we apply EVERY move
	# and revisit if a specific trailer pattern is later proven to be
	# an animation-only cue.
	var t: Tween = null
	if mode == "absolute":
		t = actor.move_absolute(int(c.get("x", 0)), int(c.get("y", 0)), ticks, _run_mode)
	else:
		t = actor.move_relative(int(c.get("dx", 0)), int(c.get("dy", 0)), ticks, _run_mode)
	if t != null:
		_pending_tweens.append(t)

func _handle_face_actor(c: Dictionary) -> void:
	var aid: int = int(c.get("actor_id", 0))
	var is_npc: bool = int(c.get("variant", 0)) == 1
	var actor := _get_or_spawn_actor(aid, is_npc)
	actor.face(c.get("direction_name", "down"))

func _handle_visibility(c: Dictionary) -> void:
	# op_0x0c -- provisionally named `set_actor_visible`. Byte-5 flag
	# distribution across the corpus is ~50/50, consistent with a
	# show/hide toggle. The semantic mapping (0=show vs 0=hide) is
	# not yet ground-truthed; some events emit only flag=0 calls so
	# whichever direction we pick will be wrong for some events.
	var aid: int = int(c.get("actor_id", 0))
	var is_npc: bool = int(c.get("variant", 0)) == 1
	var actor := _get_or_spawn_actor(aid, is_npc)
	actor.set_visible_state(int(c.get("visible", 1)) != 0)

func _handle_camera_scroll(c: Dictionary) -> void:
	if _camera == null:
		return
	var ticks: int = int(c.get("ticks", 0))
	var flag: int = int(c.get("flag", 0))
	var target: Vector2 = _camera.position
	if flag == 0:
		# Absolute: dx/dy are interpreted as the world position to focus on.
		target = Vector2(int(c.get("dx", 0)), int(c.get("dy", 0)))
	else:
		target = _camera.position + Vector2(int(c.get("dx", 0)), int(c.get("dy", 0)))
	if ticks <= 0:
		_camera.position = target
		return
	# Camera pans are axis-sequenced (horizontal leg then vertical leg)
	# just like move_actor -- the engine doesn't do diagonal camera
	# motion in field cutscenes. ticks is frames-per-tile.
	var delta := target - _camera.position
	var t := create_tween()
	var has_x: bool = absf(delta.x) > 0.5
	var has_y: bool = absf(delta.y) > 0.5
	var leg_x_target := _camera.position + Vector2(delta.x, 0.0)
	if has_x:
		var dur_x := maxf(absf(delta.x) / TILE_SIZE * ticks / FRAMES_PER_SECOND, 1.0 / FRAMES_PER_SECOND)
		t.tween_property(_camera, "position", leg_x_target, dur_x)
	if has_y:
		var dur_y := maxf(absf(delta.y) / TILE_SIZE * ticks / FRAMES_PER_SECOND, 1.0 / FRAMES_PER_SECOND)
		t.tween_property(_camera, "position", target, dur_y)
	_pending_tweens.append(t)

func _handle_scene_config(c: Dictionary) -> void:
	# Apply each embedded move_actor frame synchronously so initial
	# party placement is in effect before any later relative move runs.
	var moves: Array = c.get("embedded_moves", [])
	for m_any in moves:
		var m: Dictionary = m_any
		var aid: int = int(m.get("actor_id", 0))
		var is_npc: bool = int(m.get("variant", 0)) == 1
		var actor := _get_or_spawn_actor(aid, is_npc)
		if m.get("mode") == "absolute":
			actor.position = Vector2(int(m.get("x", 0)), int(m.get("y", 0)))
			print("  (scene_config spawn: actor %d at %s)" % [aid, actor.position])
	# Initial camera center (06 00 07 00 <x_BE> <y_BE> in the op_0x3a
	# payload). Without this the camera defaults to (0,0) and the
	# subsequent camera_scroll pan ends up off-map.
	var cam: Dictionary = c.get("camera_position", {})
	if _camera != null and not cam.is_empty():
		_camera.position = Vector2(int(cam.get("x", 0)), int(cam.get("y", 0)))
		print("  (scene_config camera at %s)" % _camera.position)

func _handle_show_bubble(c: Dictionary) -> void:
	var aid: int = int(c.get("actor_id", 0))
	if not _actors.has(aid):
		return
	var actor: EventActor = _actors[aid]
	actor.show_bubble(int(c.get("bubble_id", 0)), int(c.get("duration", 60)))

func _handle_text(c: Dictionary) -> void:
	if _dialog_label == null:
		return
	var tid: int = int(c.get("text_id", -1))
	var raw: String = _text_strings.get(tid, c.get("text_preview", "[text %d]" % tid))
	# Strip the FFBE markup tags <name=...>, <wait=N>, <br>, etc. for now
	# so the placeholder dialog box is readable.
	var clean := raw
	clean = clean.replace("<br>", "\n")
	var rx := RegEx.new()
	rx.compile("<[^>]+>")
	clean = rx.sub(clean, "", true)
	_dialog_label.text = clean
	_set_dialog_visible(true)
	_awaiting_dialog = true

func _set_dialog_visible(v: bool) -> void:
	if _dialog_label == null:
		return
	# Toggle the parent panel (ColorRect background) so the whole
	# dialog box appears/disappears, not just the text.
	var parent := _dialog_label.get_parent()
	if parent is CanvasItem:
		(parent as CanvasItem).visible = v
	else:
		_dialog_label.visible = v
