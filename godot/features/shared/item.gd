extends Control

signal pressed

const EQUIPMENT_ICON_BASE_PATH: String = "res://assets/equip/"
const UI_UNIT_BASE_PATH: String = "res://assets/ui/unit/"
const CORE_STAT_KEYS: Array[String] = ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]

const STAT_LABEL_SUFFIXES: Dictionary = {
	"HP": "hp",
	"MP": "mp",
	"ATK": "attack",
	"DEF": "defense",
	"MAG": "magic",
	"SPR": "mind"
}

const SLOT_BADGE_BY_SLOT: Dictionary = {
	"Weapon": "rhand",
	"Shield": "lhand",
	"Headgear": "head",
	"Chest": "body",
	"Accessory": "accessory1",
	"Materia": "materia1"
}

const TYPE_BADGE_BY_ICON_NAME: Dictionary = {
	"accessory.png": "accessory",
	"axe.png": "axe",
	"bow.png": "bow",
	"clothes.png": "clothes",
	"dagger.png": "ssword",
	"fist.png": "knucle",
	"greatSword.png": "msword",
	"gun.png": "gun",
	"hammer.png": "hammer",
	"harp.png": "instrument",
	"hat.png": "cap",
	"heavyArmor.png": "harmor",
	"heavyShield.png": "hshield",
	"helm.png": "helmet",
	"katana.png": "jsword",
	"lightArmor.png": "larmor",
	"lightShield.png": "lshield",
	"mace.png": "mace",
	"materia.png": "visioncard",
	"robe.png": "robe",
	"rod.png": "wand",
	"spear.png": "spear",
	"staff.png": "rod",
	"sword.png": "lsword",
	"throwing.png": "throw",
	"visionCard.png": "visioncard",
	"whip.png": "whip"
}

const TYPE_BADGE_BY_TYPE_NAME: Dictionary = {
	"Accessory": "accessory",
	"Axe": "axe",
	"Bow": "bow",
	"Clothes": "clothes",
	"Cloth Armor": "clothes",
	"Fist Weapon": "knucle",
	"Great Sword": "msword",
	"Gun": "gun",
	"Hammer": "hammer",
	"Hat": "cap",
	"Heavy Armor": "harmor",
	"Heavy Shield": "hshield",
	"Helm": "helmet",
	"Instrument": "instrument",
	"Katana": "jsword",
	"Light Armor": "larmor",
	"Light Shield": "lshield",
	"Mace": "mace",
	"Materia": "visioncard",
	"Robe": "robe",
	"Rod": "wand",
	"Short Sword": "ssword",
	"Spear": "spear",
	"Staff": "rod",
	"Sword": "lsword",
	"Throwing Weapon": "throw",
	"Vision Card": "visioncard",
	"Whip": "whip"
}

@onready var item_icon: TextureRect = $unit_equip_list_item
@onready var item_count_label: Label = $unit_equip_list_item_count
@onready var equip_name: Label = $unit_equip_list_name_text
@onready var unit_equip_cat: TextureRect = $UnitEquipCategory
@onready var equip_cat: TextureRect = $EquipCategory
@onready var equipped_to: TextureRect = $EquippedTo
@onready var prop_label_1: TextureRect = $unit_equip_list_property1_label
@onready var prop_number_1: Label = $unit_equip_list_property1_number
@onready var prop_label_2: TextureRect = $unit_equip_list_property2_label
@onready var prop_number_2: Label = $unit_equip_list_property2_number
@onready var detail_label: Label = $unit_equip_list_property3_text
@onready var click_area: Button = $ClickArea

var _texture_cache: Dictionary = {}

func _ready() -> void:
	_reset_visual_state()
	if click_area != null:
		click_area.pressed.connect(_on_click_area_pressed)

func set_clickable(enabled: bool) -> void:
	if not is_node_ready():
		await ready
	if click_area == null:
		return
	click_area.disabled = not enabled
	click_area.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE

# Instantiate, add_child, then call setup so @onready node references are valid.
func setup_from_item_data(item_data: Dictionary, display_options: Dictionary = {}) -> void:
	if not is_node_ready():
		await ready

	_reset_visual_state()

	equip_name.text = str(item_data.get("name", "Unknown Equipment"))
	detail_label.text = _build_detail_text(item_data, display_options)

	_apply_item_icon(item_data)
	_apply_quantity(display_options)
	_apply_slot_badge(item_data, display_options)
	_apply_type_badge(item_data, display_options)
	_apply_primary_stats(item_data)
	_apply_equipped_to(item_data, display_options)

func setup_placeholder(title: String, detail_text: String = "", display_options: Dictionary = {}) -> void:
	if not is_node_ready():
		await ready

	_reset_visual_state()

	equip_name.text = title
	detail_label.text = detail_text

	var icon_path: String = str(display_options.get("icon_path", ""))
	if icon_path != "":
		item_icon.texture = _load_texture(icon_path)

	var quantity: int = int(display_options.get("quantity", 0))
	if quantity > 0:
		item_count_label.text = "x%d" % quantity
		item_count_label.show()

	if bool(display_options.get("show_slot_badge", true)):
		var slot_badge_path: String = str(display_options.get("slot_badge_path", ""))
		if slot_badge_path == "":
			var slot_badge_key: String = str(display_options.get("slot_badge", ""))
			if slot_badge_key != "":
				slot_badge_path = "%sunit_equip_category_%s.tres" % [UI_UNIT_BASE_PATH, slot_badge_key]
		if slot_badge_path != "":
			unit_equip_cat.texture = _load_texture(slot_badge_path)
			unit_equip_cat.visible = unit_equip_cat.texture != null
	else:
		unit_equip_cat.hide()

	var type_badge_path: String = str(display_options.get("type_badge_path", ""))
	if type_badge_path != "":
		equip_cat.texture = _load_texture(type_badge_path)
		equip_cat.visible = equip_cat.texture != null

func _reset_visual_state() -> void:
	if item_icon != null:
		item_icon.texture = null
	if item_count_label != null:
		item_count_label.hide()
	if equip_name != null:
		equip_name.text = "Unknown Equipment"
	if unit_equip_cat != null:
		unit_equip_cat.texture = null
		unit_equip_cat.hide()
	if equip_cat != null:
		equip_cat.texture = null
		equip_cat.hide()
	if equipped_to != null:
		equipped_to.texture = null
		equipped_to.hide()
	if prop_label_1 != null:
		prop_label_1.hide()
	if prop_number_1 != null:
		prop_number_1.hide()
		prop_number_1.text = ""
	if prop_label_2 != null:
		prop_label_2.hide()
	if prop_number_2 != null:
		prop_number_2.hide()
		prop_number_2.text = ""
	if detail_label != null:
		detail_label.text = ""
	if click_area != null:
		click_area.disabled = true
		click_area.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _apply_item_icon(item_data: Dictionary) -> void:
	var icon_name: String = str(item_data.get("icon", ""))
	if icon_name == "":
		return

	var icon_path: String = EQUIPMENT_ICON_BASE_PATH + icon_name
	item_icon.texture = _load_texture(icon_path)

func _apply_quantity(display_options: Dictionary) -> void:
	var show_quantity: bool = bool(display_options.get("show_quantity", false))
	var quantity: int = int(display_options.get("quantity", 0))
	if not show_quantity or quantity <= 0:
		return

	item_count_label.text = "x%d" % quantity
	item_count_label.show()

func _apply_slot_badge(item_data: Dictionary, display_options: Dictionary) -> void:
	if not bool(display_options.get("show_slot_badge", true)):
		unit_equip_cat.hide()
		return

	var badge_key: String = str(display_options.get("slot_badge", ""))
	if badge_key == "":
		badge_key = _resolve_slot_badge_key(item_data)
	if badge_key == "":
		return

	var texture_path: String = "%sunit_equip_category_%s.tres" % [UI_UNIT_BASE_PATH, badge_key]
	unit_equip_cat.texture = _load_texture(texture_path)
	unit_equip_cat.visible = unit_equip_cat.texture != null

func _apply_type_badge(item_data: Dictionary, display_options: Dictionary) -> void:
	var badge_key: String = str(display_options.get("type_badge", ""))
	if badge_key == "":
		badge_key = _resolve_type_badge_key(item_data)
	if badge_key == "":
		return

	var texture_path: String = "%sequip_category_%s.tres" % [UI_UNIT_BASE_PATH, badge_key]
	equip_cat.texture = _load_texture(texture_path)
	equip_cat.visible = equip_cat.texture != null

func _apply_primary_stats(item_data: Dictionary) -> void:
	var primary_stats: Array[Dictionary] = _extract_primary_stats(item_data)
	if primary_stats.is_empty():
		return

	_apply_single_stat(prop_label_1, prop_number_1, primary_stats[0])
	if primary_stats.size() > 1:
		_apply_single_stat(prop_label_2, prop_number_2, primary_stats[1])

func _apply_equipped_to(item_data: Dictionary, display_options: Dictionary) -> void:
	var equipped_to_unit_id: String = str(display_options.get("equipped_to_unit_id", ""))
	if equipped_to_unit_id == "":
		equipped_to_unit_id = str(item_data.get("equipped_to", ""))
	
	if equipped_to_unit_id == "":
		return
	
	# Find the unit by instance_id in UnitService's owned_units_ids
	var unit_inst: Dictionary = {}
	for unit in UnitService.owned_units_ids:
		if str(unit.get("instance_id", "")) == equipped_to_unit_id:
			unit_inst = unit
			break
	
	if unit_inst.is_empty():
		return
	
	var entry_id: String = UnitService.get_entry_id(unit_inst)
	if entry_id == "":
		return
	
	var icon_path: String = "res://assets/unit_icons/unit_icon_%s.png" % entry_id
	equipped_to.texture = _load_texture(icon_path)
	if equipped_to.texture != null:
		equipped_to.show()

func _apply_single_stat(label_rect: TextureRect, value_label: Label, stat_info: Dictionary) -> void:
	var stat_key: String = str(stat_info.get("key", ""))
	var stat_value: int = int(stat_info.get("value", 0))
	if stat_key == "" or stat_value == 0:
		return

	var label_texture_path: String = _build_stat_label_path(stat_key)
	label_rect.texture = _load_texture(label_texture_path)
	label_rect.show()
	value_label.text = str(stat_value)
	value_label.show()

func _extract_primary_stats(item_data: Dictionary) -> Array[Dictionary]:
	var stats_value: Variant = item_data.get("stats", {})
	if not (stats_value is Dictionary):
		return []

	var stats: Dictionary = stats_value as Dictionary
	var primary_stats: Array[Dictionary] = []
	for stat_key in CORE_STAT_KEYS:
		var stat_value: int = int(stats.get(stat_key, 0))
		if stat_value == 0:
			continue
		primary_stats.append({"key": stat_key, "value": stat_value})
		if primary_stats.size() == 2:
			break

	return primary_stats

func _build_detail_text(item_data: Dictionary, display_options: Dictionary) -> String:
	var override_text: String = str(display_options.get("detail_text", ""))
	if override_text != "":
		return override_text

	var strings_value: Variant = item_data.get("strings", {})
	if strings_value is Dictionary:
		var strings: Dictionary = strings_value as Dictionary
		var short_desc_value: Variant = strings.get("desc_short", [])
		if short_desc_value is Array and not short_desc_value.is_empty():
			return str(short_desc_value[0])

	var summary_parts: PackedStringArray = []
	var type_text: String = str(item_data.get("type", ""))
	var slot_text: String = str(item_data.get("slot", ""))
	if type_text != "":
		summary_parts.append(type_text)
	if slot_text != "":
		summary_parts.append(slot_text)
	if bool(item_data.get("is_twohanded", false)):
		summary_parts.append("Two-Handed")

	if summary_parts.is_empty():
		return "No description."

	return " • ".join(summary_parts)

func _resolve_slot_badge_key(item_data: Dictionary) -> String:
	var slot_text: String = str(item_data.get("slot", ""))
	return str(SLOT_BADGE_BY_SLOT.get(slot_text, ""))

func _resolve_type_badge_key(item_data: Dictionary) -> String:
	var type_icon_name: String = str(item_data.get("type_icon", ""))
	if type_icon_name != "":
		var badge_key_from_icon: String = str(TYPE_BADGE_BY_ICON_NAME.get(type_icon_name, ""))
		if badge_key_from_icon != "":
			return badge_key_from_icon

	var type_name: String = str(item_data.get("type", ""))
	return str(TYPE_BADGE_BY_TYPE_NAME.get(type_name, ""))

func _build_stat_label_path(stat_key: String) -> String:
	var suffix: String = str(STAT_LABEL_SUFFIXES.get(stat_key, ""))
	if suffix == "":
		return ""
	return "%sunit_status_label_%s.tres" % [UI_UNIT_BASE_PATH, suffix]

func _load_texture(resource_path: String) -> Texture2D:
	if resource_path == "":
		return null
	if _texture_cache.has(resource_path):
		return _texture_cache[resource_path]
	if not ResourceLoader.exists(resource_path):
		_texture_cache[resource_path] = null
		return null

	var texture: Texture2D = ResourceLoader.load(resource_path) as Texture2D
	_texture_cache[resource_path] = texture
	return texture

func _on_click_area_pressed() -> void:
	pressed.emit()
