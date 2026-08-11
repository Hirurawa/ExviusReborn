extends Area2D

# Click-to-open treasure chest, built by tile_map.gd._spawn_chests() from a
# blueprint `dynamic_entities` record of kind "chest".
#
# map.bin gives each chest two ids:
#   treasure_id     -> field_treasure row, which holds the reward
#                      ("type:id:amount:rate")
#   open_switch_id  -> the switch that records it as looted, and whose
#                      switch.switchType picks the sprite
#
# State lives in SwitchService (persisted to switches.json), so a chest opened
# once stays open across sessions and across chunk redraws.
#
# Like npc_interactable.gd this Area2D is pick-only: `monitoring`/`monitorable`
# stay off so it never blocks the player's movement.

const DialogueBoxScript := preload("res://features/town/dialogue_box.gd")

# Shared spritesheet for common map objects (chests, monuments, sparkles).
# 986x986 = a 17x17 grid of 58px tiles, the same tile size the town maps use.
const SHEET_PATH: String = "res://assets/map_common/map_obj_basic.png"
const SHEET_TILE: int = 58
const COL_CLOSED: int = 1
const COL_OPEN: int = 7

# switch.switchType -> spritesheet row. The sheet holds three chest styles:
# row 1 wooden, row 3 blue/gold (has a keyplate), row 5 green with a gem.
const ROW_BY_SWITCH_TYPE: Dictionary = {
	400: 1, 401: 1,    # 宝箱 — ordinary chest
	410: 3, 411: 3,    # 鍵宝箱 — locked chest
	520: 3,            # 貸金庫 — strongbox / vault
	500: 5, 501: 5,    # メダル — medal / star quartz
	510: 5,            # クレスト — crest
}
const ROW_DEFAULT: int = 1

var treasure_id: int = 0
var open_switch_id: int = 0

var _sprite: Sprite2D
var _sheet: Texture2D
var _opened: bool = false
var _popup_open: bool = false


func _ready() -> void:
	input_pickable = true
	monitoring = false
	monitorable = false
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


## Builds the chest's sprite and initial open/closed state. Called by the
## spawner before the node enters the tree.
func setup(entity: Dictionary) -> void:
	treasure_id = int(entity.get("treasure_id", 0))
	open_switch_id = int(entity.get("open_switch_id", 0))
	_opened = open_switch_id > 0 and SwitchService.is_unlocked(str(open_switch_id))

	_sheet = load(SHEET_PATH)
	if _sheet == null:
		push_warning("TreasureChest: missing spritesheet %s" % SHEET_PATH)
		return
	_sprite = Sprite2D.new()
	_sprite.texture = _frame(_opened)
	# Top-left anchored to match how NPC sprites are placed, so the Area2D's
	# position is the blueprint's (source_x_px, source_y_px).
	_sprite.centered = false
	add_child(_sprite)


func _frame(opened: bool) -> AtlasTexture:
	var row: int = ROW_BY_SWITCH_TYPE.get(GameDatabase.get_switch_type(open_switch_id), ROW_DEFAULT)
	var col: int = COL_OPEN if opened else COL_CLOSED
	var atlas := AtlasTexture.new()
	atlas.atlas = _sheet
	atlas.region = Rect2(col * SHEET_TILE, row * SHEET_TILE, SHEET_TILE, SHEET_TILE)
	return atlas


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _popup_open:
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	_open()
	get_viewport().set_input_as_handled()


func _open() -> void:
	if _opened:
		_show_message("The chest is empty.")
		return

	var treasure: Dictionary = GameDatabase.get_field_treasure(treasure_id)
	if treasure.is_empty():
		push_warning("TreasureChest: no field_treasure row for treasureId %d" % treasure_id)
		_show_message("The chest is empty.")
		return

	# field_treasure.reward is a single "type:id:amount:rate" entry.
	var info: Dictionary = RewardGranter.grant(str(treasure.get("reward", "")).split(":"))
	InventoryService.emit_updated()
	PlayerProfile.emit_all()

	_opened = true
	if open_switch_id > 0:
		SwitchService.unlock_switches(str(open_switch_id), "open_treasure_chest")
	if _sprite != null:
		_sprite.texture = _frame(true)

	var amount: int = int(info.get("amount", 1))
	var name_text: String = str(info.get("name", ""))
	var message: String = "Found %s x%d!" % [name_text, amount] if amount > 1 else "Found %s!" % name_text
	if not bool(info.get("granted", false)):
		# Key items, recipes and vision cards have no player-side storage yet —
		# name what was in the chest rather than silently hand over nothing.
		message += "\n(Not added to your inventory yet.)"
	_show_message(message)


func _show_message(body: String) -> void:
	var box := DialogueBoxScript.new()
	_find_ui_root().add_child(box)
	box.show_pages([{"speaker": "", "body": body}])
	_popup_open = true
	box.closed.connect(func(): _popup_open = false)


func _on_mouse_entered() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)


func _on_mouse_exited() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


# Park the popup high in the tree so a chunk redraw (which frees the chest
# container) doesn't take it down with it. Mirrors npc_interactable.gd.
func _find_ui_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return self
	var root := tree.current_scene
	return root if root != null else self
