extends Control

signal pressed

const ICON_BASE_PATH: String = "res://assets/abilities/"
const BUTTON_ITEM_BACKGROUND: Texture2D = preload("res://assets/ui/common/button_item1.tres")
const BUTTON_LIMIT_BACKGROUND: Texture2D = preload("res://assets/ui/common/button_limit1.tres")
const BUTTON_ESPER_BACKGROUND: Texture2D = preload("res://assets/ui/common/button_summag1.tres")
const LACK_MP_TEXTURE: Texture2D = preload("res://assets/ui/battle/lack_mp.tres")
const LACK_LIMIT_TEXTURE: Texture2D = preload("res://assets/ui/battle/lack_limit.tres")
const LACK_SUMMON_TEXTURE: Texture2D = preload("res://assets/ui/battle/lack_summon.tres")

const REASON_NONE: String = ""
const REASON_LACK_MP: String = "lack_mp"
const REASON_LACK_LIMIT: String = "lack_limit"
const ROLE_STANDARD: String = "standard"
const ROLE_LIMITBURST: String = "limitburst"
const ROLE_ESPER: String = "esper_skill"

@onready var background_rect: TextureRect = $unit_magic_bg_1
@onready var category_rect: TextureRect = $unit_magic_category_1
@onready var icon: TextureRect = $unit_magic_icon_1
@onready var unavailable_reason_rect: TextureRect = $unit_magic_unavailable_reason_1
@onready var name_label: Label = $unit_magic_name_text_1
@onready var mp_label: Label = $unit_magic_mp_number_1
@onready var mp_icon:TextureRect = $unit_magic_mp_1
@onready var detail_label: Label = $unit_magic_detail_text_1
@onready var level_icon: TextureRect = $unit_magic_icon
@onready var level_banner: TextureRect = $unit_magic_lv
@onready var level_label: Label = $unit_magic_lv_num
@onready var action_button: Button = $Button

var _disabled_reason: String = REASON_NONE

func _ready() -> void:
	action_button.pressed.connect(_on_action_button_pressed)
	level_icon.hide()
	level_banner.hide()
	level_label.hide()
	_apply_skill_role_style(ROLE_STANDARD)
	_apply_action_state(true, REASON_NONE)

func setup_from_skill_data(skill_data: Dictionary, source: String = "", is_button: bool = false) -> void:
	if not is_node_ready():
		await ready

	_apply_skill_role_style(ROLE_STANDARD)
	_apply_action_state(true, REASON_NONE)

	name_label.text = str(skill_data.get("name", "Unknown Magic"))
	
	var icon_path = "res://assets/abilities/" + skill_data.get("icon", "ability_1.png")
	var icon_tex = load(icon_path)
	if icon_tex:
		icon.texture = icon_tex
		
	if source != "":
		var texname = source
		if texname == "Trait":
			texname = "chara"
		if texname == "Equip":
			texname = "weapon"
		if texname == "Esper":
			texname = "summons"
		var cat_icon_path = "res://assets/ui/unit/unit_magic_category_" + texname + ".tres"
		var cat_tex = load(cat_icon_path)
		if cat_tex:
			category_rect.texture = cat_tex
	
	var mp_value = _build_mp_text(skill_data)
	if mp_value != "--":
		mp_label.text = mp_value
	else:
		mp_label.hide()
		mp_icon.hide()
	
	if skill_data.get("rarity", -1) > 0:
		level_label.text = str(skill_data.get("rarity"))
		level_label.show()
		level_icon.show()
		level_banner.show()
	else:
		level_icon.hide()
		level_banner.hide()
		level_label.hide()
	
	var orb_icon_path = "res://assets/ui/unit/unit_magic_icon_" + str(skill_data.get("magic_type", "")).to_lower() + ".tres"
	if ResourceLoader.exists(orb_icon_path):
		var orb_tex = load(orb_icon_path)
		if orb_tex:
			level_icon.texture = orb_tex
	else:
		level_icon.hide()
		level_banner.hide()
		level_label.hide()
		
	detail_label.text = _build_description_text(skill_data)
	
	action_button.visible = is_button
	action_button.mouse_filter = Control.MOUSE_FILTER_STOP if is_button else Control.MOUSE_FILTER_IGNORE

func _on_action_button_pressed() -> void:
	pressed.emit()

func set_action_enabled(enabled: bool) -> void:
	if not is_node_ready():
		await ready
	if action_button == null:
		push_error("Skill: action_button is missing, cannot update enabled state.")
		return
	if enabled:
		_disabled_reason = REASON_NONE
	_apply_action_state(enabled, _disabled_reason)

func set_skill_role_style(role_type: String) -> void:
	if not is_node_ready():
		await ready
	_apply_skill_role_style(role_type)

func set_action_availability(enabled: bool, disabled_reason: String = REASON_NONE) -> void:
	if not is_node_ready():
		await ready
	_disabled_reason = disabled_reason if not enabled else REASON_NONE
	_apply_action_state(enabled, _disabled_reason)

func _apply_skill_role_style(role_type: String) -> void:
	if background_rect == null:
		return
	if role_type == ROLE_LIMITBURST:
		background_rect.texture = BUTTON_LIMIT_BACKGROUND
	elif role_type == ROLE_ESPER:
		background_rect.texture = BUTTON_ESPER_BACKGROUND
	else:
		background_rect.texture = BUTTON_ITEM_BACKGROUND

func _apply_action_state(enabled: bool, disabled_reason: String) -> void:
	if action_button != null:
		action_button.disabled = not enabled
		action_button.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE

	if unavailable_reason_rect != null:
		if enabled or disabled_reason == REASON_NONE:
			unavailable_reason_rect.hide()
		elif disabled_reason == REASON_LACK_LIMIT:
			unavailable_reason_rect.texture = LACK_LIMIT_TEXTURE
			unavailable_reason_rect.show()
		else:
			unavailable_reason_rect.texture = LACK_MP_TEXTURE
			unavailable_reason_rect.show()

	modulate = Color(1.0, 1.0, 1.0, 1.0) if enabled else Color(0.45, 0.45, 0.45, 1.0)

func _build_mp_text(skill_data: Dictionary) -> String:
	var cost: Variant = skill_data.get("cost", {})
	if cost is Dictionary and cost.has("MP"):
		return str(int(cost["MP"]))
	return "--"

func _build_description_text(skill_data: Dictionary) -> String:
	var description_text: String = str(skill_data.get("description", "")).strip_edges()
	if description_text != "":
		return description_text

	var effects: Variant = skill_data.get("effects", [])
	if effects is Array and not effects.is_empty():
		var first_effect: Variant = effects[0]
		if first_effect is Array and not first_effect.is_empty():
			return str(first_effect[0])
		if first_effect is String:
			return str(first_effect)
	return "No description."
