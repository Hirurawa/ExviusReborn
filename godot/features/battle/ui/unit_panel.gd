extends TextureRect

class_name UnitPanel

## One party member's panel in the battle screen's bottom area: portrait, name, HP, MP
## and limit gauges, the queued command's icon, and the gestures (swipe up: attack,
## down: defend, right: skills, left: items, tap: act or, while an ally is being picked,
## pick this one). It knows nothing about the battle: the screen pushes values in and
## acts on the signals.

## Swipe up or down: `command` is ATTACK or DEFEND.
signal command_chosen(slot: int, command: StringName)
signal open_skill_menu(slot: int)
signal open_item_menu(slot: int)
signal panel_tapped(slot: int)

const ATTACK: StringName = &"attack"
const DEFEND: StringName = &"defend"

## Command icons (assets/ui/battle/battle_com_icon_<name>.tres).
const ICON_ATTACK: String = "attack"
const ICON_DEFEND: String = "defense"

const SWIPE_THRESHOLD: float = 20.0
const TAP_MAX_DISTANCE: float = 8.0
const ACTED_COLOR := Color(0.5, 0.5, 0.5, 1.0)
const VALID_TARGET_COLOR := Color(0.5, 1.0, 0.5, 1.0)

@onready var unit_thum: TextureRect = $UnitThum
@onready var unit_name: Label = $UnitName
@onready var hp_gage: TextureRect = $HPGage
@onready var hp_now: Label = $HPNow
@onready var hp_slash: TextureRect = $HPSlash
@onready var hp_max: Label = $HPMax
@onready var mp_gage: TextureRect = $MPGage
@onready var mp_now: Label = $MPNow
@onready var limit_gage: TextureRect = $LimitGage
@onready var barrier_gage: TextureRect = $BarrierGage
@onready var cmd_baloon: TextureRect = $CmdBaloon
@onready var hp_bar: Sprite2D = $BattleUnitHpBar1
@onready var mp_bar: Sprite2D = $BattleUnitMpBar
@onready var limit_bar: Sprite2D = $BattleUnitLimitBar
@onready var barrier_bar: Sprite2D = $BattleUnitBarrierBar

var is_ally_targeting_mode: bool = false
var is_valid_target: bool = false

var _slot: int = -1
var _is_dragging: bool = false
var _drag_start_position: Vector2 = Vector2.ZERO
## Greyed: the member has acted, or cannot take commands this turn.
var _acted: bool = false
## KO'd (HP 0): no gestures, except as an ally pick.
var _down: bool = false
var _shown_icon: String = ICON_ATTACK


## `slot` names the panel in its signals; `template_id` (the unit id) picks the portrait.
func setup(slot: int, template_id: String = "") -> void:
	_slot = slot
	if template_id != "":
		var texture_path: String = "res://assets/unit_icons/unit_icon_%s.png" % template_id
		if ResourceLoader.exists(texture_path):
			unit_thum.texture = ResourceLoader.load(texture_path)
	_update_visual_state()


func show_stats(member_name: String, cur_hp: int, max_hp: int, cur_mp: int, max_mp: int, cur_lb: int, max_lb: int) -> void:
	unit_name.text = member_name
	hp_now.text = str(cur_hp)
	hp_max.text = str(max_hp)
	mp_now.text = str(cur_mp)
	_down = cur_hp <= 0
	set_hp_display(cur_hp, max_hp)
	set_mp_display(cur_mp, max_mp)
	set_limit_gauge(cur_lb, max_lb)


## The queued command's icon: attack, defense, magic, special, limit, summon or item.
func show_command(icon: String) -> void:
	_shown_icon = icon
	var icon_path: String = "res://assets/ui/battle/battle_com_icon_%s.tres" % icon
	if ResourceLoader.exists(icon_path):
		cmd_baloon.texture = ResourceLoader.load(icon_path)


## Greys the panel and stops its gestures (it has acted, or cannot take commands).
func set_acted(acted: bool) -> void:
	_acted = acted
	_update_visual_state()


func set_ally_targeting_mode(active: bool, valid: bool = false) -> void:
	is_ally_targeting_mode = active
	is_valid_target = valid
	_update_visual_state()


func _gui_input(event: InputEvent) -> void:
	if _slot < 0:
		return
	if (_acted or _down) and not is_ally_targeting_mode:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging = false
			_drag_start_position = event.position
		else:
			if not _is_dragging and (event.position - _drag_start_position).length() <= TAP_MAX_DISTANCE:
				panel_tapped.emit(_slot)
			_is_dragging = false

	elif (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) or event is InputEventScreenDrag:
		if _acted or _down or _is_dragging:
			return
		var diff: Vector2 = event.position - _drag_start_position
		if abs(diff.y) > SWIPE_THRESHOLD and abs(diff.y) > abs(diff.x):
			_is_dragging = true
			if diff.y > 0.0 and _shown_icon != ICON_DEFEND:
				command_chosen.emit(_slot, DEFEND)
			elif diff.y < 0.0 and _shown_icon != ICON_ATTACK:
				command_chosen.emit(_slot, ATTACK)
		elif abs(diff.x) > SWIPE_THRESHOLD and abs(diff.x) > abs(diff.y):
			_is_dragging = true
			if diff.x > 0.0:
				open_skill_menu.emit(_slot)
			else:
				open_item_menu.emit(_slot)


func _update_visual_state() -> void:
	if is_ally_targeting_mode:
		modulate = VALID_TARGET_COLOR if is_valid_target else ACTED_COLOR
	elif _acted:
		modulate = ACTED_COLOR
	else:
		modulate = Color.WHITE


func set_hp_display(current_hp: int, max_hp: int) -> void:
	if max_hp <= 0:
		return
	hp_bar.scale.x = clampf(float(current_hp) / float(max_hp), 0.0, 1.0)


func set_mp_display(current_mp: int, max_mp: int) -> void:
	if max_mp <= 0:
		return
	mp_bar.scale.x = clampf(float(current_mp) / float(max_mp), 0.0, 1.0)


func set_limit_gauge(current_limit: int, max_limit: int) -> void:
	if max_limit <= 0:
		return
	limit_bar.scale.x = clampf(float(current_limit) / float(max_limit), 0.0, 1.0)


func set_barrier_gauge(current_barrier: float) -> void:
	var is_active: bool = current_barrier > 0.0
	barrier_gage.visible = is_active
	barrier_bar.visible = is_active
	if is_active:
		barrier_gage.modulate.a = clampf(current_barrier, 0.0, 1.0)
		barrier_bar.scale.x = clampf(current_barrier, 0.0, 1.0)
