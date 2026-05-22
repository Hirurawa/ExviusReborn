extends CharacterBody2D

@export var walk_speed: float = 250.0
@export var run_speed: float = 300.0
@onready var anim = $AnimatedSprite2D
var last_direction: String = "up"

# Cached reference to the active TileMap (for grid-event lookups).
var _tile_map: Node = null
# Set true by _apply_grid_event_constraint when the input direction was
# actually re-mapped to a stair/ladder axis. Used to gate the
# collision-bypass step so wall-clipping only happens while genuinely
# traversing the event corridor.
var _constraint_locked: bool = false

func _ready() -> void:
	# tile_map renders layers with an interleaved z scheme:
	#   visual layer N -> z = 2*N        static layer N -> z = 2*N + 1
	# We want the player above everything in layer 2 (ground decor like
	# trees, lampposts) but below layer 3 (rooftops/overhangs), so z=5
	# (level with static layer 2 but above visual layer 2 at z=4).
	z_index = 5
	# Register so the tile_map's warp Area2D triggers can identify us.
	add_to_group("player")

func _physics_process(delta: float) -> void:
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	# Locate any grid event under or adjacent to the player and snap the
	# body onto its corridor centerline. This keeps the collision shape
	# inside the walkable strip instead of drifting into the bordering
	# walls when the player enters a stair off-center.
	var hit := _find_grid_event_cell()
	var on_event: bool = hit["eid"] != 0

	# Apply stair/ladder movement restrictions if the player stands
	# on a grid-event tile. Sets _constraint_locked as a side effect.
	direction = _apply_grid_event_constraint(direction)

	# Snap to the corridor centerline only when the constraint actually
	# locks the direction. If the player is on the last tile of the run
	# and trying to step off, _constraint_locked is false and we must
	# leave the body alone so it can exit; otherwise the snap would
	# repeatedly yank it back onto the centerline.
	if on_event and _constraint_locked:
		_snap_to_corridor(int(hit["eid"]), hit["cell"] as Vector2i)
	
	# Check if the player is holding the run button we defined in the Input Map
	var is_running = Input.is_action_pressed("run")
	
	# Dynamically set the speed based on the button state
	var current_speed = run_speed if is_running else walk_speed
	
	velocity = direction * current_speed

	# Bypass physics for the entire duration the player stands on a grid
	# event tile. Mid-traversal this prevents the diagonal corridor's
	# flanking walls from blocking motion; at the end tile it prevents
	# depenetration from shoving the player backward along the stair
	# axis when they try to step off (the body's collision shape is
	# legitimately overlapping the corridor walls). The constraint logic
	# already restricts movement direction while locked, so bypassing
	# collision here cannot lead the player off-corridor mid-run.
	if on_event:
		position += velocity * delta
	else:
		move_and_slide()
	
	# Pass BOTH the direction and the running state to the animation handler
	update_animation(direction, is_running)

	# Push the player's grid-space position to the minimap (if present).
	_update_minimap_marker()


func _update_minimap_marker() -> void:
	if not is_instance_valid(_tile_map):
		_tile_map = get_tree().get_first_node_in_group("tile_map")
		if not is_instance_valid(_tile_map):
			return
	var ts: int = int(_tile_map.tile_size)
	if ts <= 0:
		return
	var minimap_node := get_tree().get_first_node_in_group("minimap")
	if minimap_node == null:
		return
	# Position is already in world (= tile-grid * tile_size) space, so a
	# straight divide gives fractional tile coordinates.
	var grid_pos: Vector2 = global_position / float(ts)
	minimap_node.set_player_grid_pos(grid_pos)


# Returns the event_id of any grid event under or immediately adjacent
# to the player's collision shape, or 0 if none.
func _current_grid_event() -> int:
	return _find_grid_event_cell()["eid"]


# Multi-probe variant of _current_grid_event that also returns the
# specific cell that produced the hit. Returns {"eid": int, "cell": Vector2i}.
# Multi-sampled so that during a diagonal stair traversal the lookup
# stays sticky even when the body center momentarily crosses through
# the corner wall cell between two consecutive stair tiles.
func _find_grid_event_cell() -> Dictionary:
	var miss := {"eid": 0, "cell": Vector2i.ZERO}
	if not is_instance_valid(_tile_map):
		_tile_map = get_tree().get_first_node_in_group("tile_map")
		if not is_instance_valid(_tile_map):
			return miss
	var tile_size: int = int(_tile_map.tile_size)
	if tile_size <= 0:
		return miss
	var shape_node: CollisionShape2D = null
	for c in get_children():
		if c is CollisionShape2D:
			shape_node = c
			break
	var center_global: Vector2 = global_position if shape_node == null else shape_node.global_position
	var d: float = float(tile_size) * 0.5 - 4.0
	# 5 probes: center + 4 diagonal offsets just shy of half a tile.
	var probes := [
		center_global,
		center_global + Vector2(-d, -d),
		center_global + Vector2( d, -d),
		center_global + Vector2(-d,  d),
		center_global + Vector2( d,  d),
	]
	for p in probes:
		var local: Vector2 = _tile_map.to_local(p)
		var cell := Vector2i(int(floor(local.x / tile_size)), int(floor(local.y / tile_size)))
		var eid: int = _tile_map.get_grid_event_at(cell)
		if eid != 0:
			return {"eid": eid, "cell": cell}
	return miss


# Snap input direction to the axis allowed by the grid-event under the
# player's current tile. Returns the original direction if no event applies
# OR if the next tile in the constrained direction is not itself a grid
# event (i.e. the player has reached the end of the stair/ladder run and
# should be free to step off).
#   id 1: diagonal stair, top-left <-> bottom-right  (allowed: ↘ / ↖)
#   id 2: diagonal stair, bottom-left <-> top-right  (allowed: ↗ / ↙)
#   id 3: vertical ladder body                       (allowed: ↑ / ↓)
#   id 4: ladder anchor (top/bottom entry)           (allowed: ↑ / ↓)
func _apply_grid_event_constraint(dir: Vector2) -> Vector2:
	_constraint_locked = false
	if dir == Vector2.ZERO:
		return dir

	var hit := _find_grid_event_cell()
	var eid: int = hit["eid"]
	if eid == 0:
		return dir

	var constrained: Vector2 = Vector2.ZERO
	match eid:
		1:
			var s := signf(dir.x + dir.y)
			if s == 0.0:
				return Vector2.ZERO
			constrained = Vector2(s, s).normalized()
		2:
			var s2 := signf(dir.x - dir.y)
			if s2 == 0.0:
				return Vector2.ZERO
			constrained = Vector2(s2, -s2).normalized()
		3, 4:
			if dir.y == 0.0:
				return Vector2.ZERO
			constrained = Vector2(0.0, signf(dir.y))
		_:
			return dir

	# Look one cell ahead from the cell that actually produced the hit
	# (NOT from the body center, which during a diagonal corner-crossing
	# sits in a wall tile). If that cell also carries a grid event, we're
	# still mid-run -> lock the direction. If it doesn't, the player is
	# at the end of the run and can step off freely.
	var step := Vector2i(int(round(constrained.x)), int(round(constrained.y)))
	var next_cell: Vector2i = (hit["cell"] as Vector2i) + step
	if _tile_map.get_grid_event_at(next_cell) == 0:
		return dir

	_constraint_locked = true
	return constrained


# Pull the collision shape onto the centerline of the grid-event corridor
# the player just stepped on. Without this, a player who walks onto a
# diagonal stair from the side will keep their off-center y (or x) for
# the whole traversal, drifting into the wall that flanks the corridor.
#   id 1 (TL-BR stair): centerline runs along (1, 1) through cell center
#                       => zero the perpendicular ((1,-1)/sqrt2) component
#   id 2 (BL-TR stair): centerline runs along (1,-1) through cell center
#                       => zero the perpendicular ((1, 1)/sqrt2) component
#   id 3, 4 (vertical): centerline is the cell's vertical axis
#                       => zero the x offset
func _snap_to_corridor(eid: int, cell: Vector2i) -> void:
	if not is_instance_valid(_tile_map):
		return
	var ts: float = float(_tile_map.tile_size)
	if ts <= 0.0:
		return
	var shape_node: CollisionShape2D = null
	for c in get_children():
		if c is CollisionShape2D:
			shape_node = c
			break
	if shape_node == null:
		return

	var cell_center_local := Vector2((cell.x + 0.5) * ts, (cell.y + 0.5) * ts)
	var cell_center_global: Vector2 = _tile_map.to_global(cell_center_local)
	var off: Vector2 = shape_node.global_position - cell_center_global
	var correction: Vector2 = Vector2.ZERO
	match eid:
		1:
			var p: float = (off.x - off.y) * 0.5
			correction = Vector2(-p, p)
		2:
			var p2: float = (off.x + off.y) * 0.5
			correction = Vector2(-p2, -p2)
		3, 4:
			correction = Vector2(-off.x, 0.0)
	if correction != Vector2.ZERO:
		global_position += correction


func update_animation(dir: Vector2, is_running: bool) -> void:
	if dir.length() == 0:
		anim.play("idle_" + last_direction)
		return
		
	anim.flip_h = false 
	
	# 1. Check Diagonals First
	if dir.x > 0 and dir.y < 0:
		last_direction = "up_right"
	elif dir.x > 0 and dir.y > 0:
		last_direction = "down_right"
	elif dir.x < 0 and dir.y < 0:
		last_direction = "up_left"
	elif dir.x < 0 and dir.y > 0:
		last_direction = "down_left"
		
	# 2. Fallback to Cardinals
	elif dir.x > 0:
		last_direction = "right"
	elif dir.x < 0:
		last_direction = "left"
	elif dir.y < 0:
		last_direction = "up"
	elif dir.y > 0:
		last_direction = "down"

	# 3. The Prefix Swap! 
	# Decide the first half of the animation string based on the button state
	var action_prefix = "run_" if is_running else "walk_"

	# 4. Combine the prefix and the direction (e.g., "run_" + "up_right")
	anim.play(action_prefix + last_direction)
