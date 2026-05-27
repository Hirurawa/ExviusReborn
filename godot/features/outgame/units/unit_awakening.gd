extends Control

@onready var back_button: Button = $UnitNamebgChara/UnitMinibutton1
@onready var before_stand: TextureRect = $Status/unit_classup_before_stand
@onready var before_unit: TextureRect = $Status/unit_classup_before_unit
@onready var after_stand: TextureRect = $Status/unit_classup_after_stand
@onready var after_unit: TextureRect = $Status/unit_classup_after_unit
@onready var gil_label: Label = $Button/unit_classup_need_money_number
@onready var material_nodes: Array[Control] = [
	$Material1,
	$Material2,
	$Material3,
	$Material4,
	$Material5,
]

var base_unit_instance_id: String = ""
var base_unit_inst: Dictionary = {}

var _texture_cache: Dictionary = {}

func init_scene(params: Dictionary) -> void:
	if params.has("base_unit_instance_id"):
		base_unit_instance_id = str(params.get("base_unit_instance_id", ""))
	if params.has("base_unit_inst") and params.get("base_unit_inst") is Dictionary:
		base_unit_inst = (params.get("base_unit_inst", {}) as Dictionary).duplicate(true)
	call_deferred("_refresh_before_visual")

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)

func _refresh_before_visual() -> void:
	var unit_tex: Texture2D = _get_unit_texture(base_unit_inst)
	var rarity: int = int(base_unit_inst.get("current_rarity", base_unit_inst.get("rarity", 1)))
	var next_rarity: int = min(rarity + 1, 7)
	var next_unit_tex: Texture2D = _get_unit_texture_for_rarity(base_unit_inst, next_rarity)
	if next_unit_tex == null:
		next_unit_tex = unit_tex

	if before_unit != null:
		before_unit.texture = unit_tex
	if before_stand != null:
		var ped: Texture2D = _get_pedestal_texture(rarity)
		if ped != null:
			before_stand.texture = ped

	if after_unit != null:
		after_unit.texture = next_unit_tex
	if after_stand != null:
		var next_ped: Texture2D = _get_pedestal_texture(next_rarity)
		if next_ped != null:
			after_stand.texture = next_ped

	_populate_awakening_requirements()

func _get_current_entry() -> Dictionary:
	if base_unit_inst.is_empty():
		return {}
	var unit_id: String = str(base_unit_inst.get("unit_id", ""))
	if unit_id == "":
		return {}
	var unit_data: Dictionary = StaticData.game_data_units.get(unit_id, {})
	var entries: Variant = unit_data.get("entries", {})
	if not (entries is Dictionary):
		return {}
	var rarity: int = int(base_unit_inst.get("current_rarity", base_unit_inst.get("rarity", 1)))
	for key in (entries as Dictionary).keys():
		var entry: Variant = (entries as Dictionary)[key]
		if entry is Dictionary and int((entry as Dictionary).get("rarity", -1)) == rarity:
			return entry as Dictionary
	return {}

func _populate_awakening_requirements() -> void:
	var entry: Dictionary = _get_current_entry()
	var awakening_data: Variant = entry.get("awakening", null)
	var awakening: Dictionary = awakening_data as Dictionary if awakening_data is Dictionary else {}

	if gil_label != null:
		gil_label.text = str(int(awakening.get("gil", 0)))

	var materials_var: Variant = awakening.get("materials", {})
	var materials: Dictionary = materials_var as Dictionary if materials_var is Dictionary else {}
	var material_ids: Array = materials.keys()

	for i in range(material_nodes.size()):
		var slot: Control = material_nodes[i]
		if slot == null:
			continue
		if i >= material_ids.size():
			slot.visible = false
			continue
		var item_id: String = str(material_ids[i])
		var count: int = int(materials[material_ids[i]])
		var item_data: Dictionary = StaticData.game_data_items.get(item_id, {})

		var icon_node: TextureRect = slot.get_node_or_null("unit_classup_item_icon") as TextureRect
		if icon_node != null:
			var icon_name: String = str(item_data.get("icon", ""))
			var tex: Texture2D = null
			if icon_name != "":
				tex = _load_cached_texture("res://assets/items/" + icon_name)
			icon_node.texture = tex

		var num_node: Label = slot.get_node_or_null("unit_classup_item_num") as Label
		if num_node != null:
			num_node.text = str(count)

		var name_node: Label = slot.get_node_or_null("unit_classup_item_name") as Label
		if name_node != null:
			name_node.text = str(item_data.get("name", item_id))

		slot.visible = true

func _get_unit_texture(unit_inst: Dictionary) -> Texture2D:
	if unit_inst.is_empty():
		return null
	var entry_id: String = UnitService.get_entry_id(unit_inst)
	if entry_id == "":
		return null
	var img_path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % entry_id
	return _load_cached_texture(img_path)

func _get_unit_texture_for_rarity(unit_inst: Dictionary, rarity: int) -> Texture2D:
	if unit_inst.is_empty():
		return null
	var unit_id: String = str(unit_inst.get("unit_id", ""))
	if unit_id == "":
		return null
	var unit_data: Dictionary = StaticData.game_data_units.get(unit_id, {})
	var entries: Variant = unit_data.get("entries", {})
	if entries is Dictionary:
		for key in (entries as Dictionary).keys():
			var entry: Variant = (entries as Dictionary)[key]
			if entry is Dictionary and int((entry as Dictionary).get("rarity", -1)) == rarity:
				var img_path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % str(key)
				return _load_cached_texture(img_path)
	return null

func _get_pedestal_texture(rarity: int) -> Texture2D:
	var candidate_paths: Array[String] = [
		"res://assets/ui/unit/unit_charastand_rare%s_small.tres" % rarity,
		"res://assets/ui/unit/unit_charastand_small.tres",
	]
	for path in candidate_paths:
		var tex: Texture2D = _load_cached_texture(path)
		if tex != null:
			return tex
	return null

func _load_cached_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	if not ResourceLoader.exists(path):
		_texture_cache[path] = null
		return null
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _on_back_pressed() -> void:
	UIManager.pop()
	var new_top: Node = UIManager.get_current_scene()
	if new_top and new_top.has_method("_on_awaken_units"):
		new_top.call_deferred("_on_awaken_units")
