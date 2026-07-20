extends Control

@onready var espers_list_container: GridContainer = $VBoxContainer/ScrollContainer/EspersListContainer
@onready var esper_frame_template: Button = $EsperFrame
@onready var back_button: TextureButton = $VBoxContainer/UnitNamebgChara2/BackButton

var mode: String = "view"
var target_party_index: int = -1
var target_slot_index: int = -1
var current_summon_id: String = ""
var selection_callback: Callable = Callable()
var _party_used_summons: Dictionary = {}

func init_scene(params: Dictionary) -> void:
	mode = str(params.get("mode", "view"))
	target_party_index = int(params.get("party_index", -1))
	target_slot_index = int(params.get("slot_index", -1))
	current_summon_id = str(params.get("current_summon_id", "")).strip_edges()
	if params.has("selection_callback") and params["selection_callback"] is Callable:
		selection_callback = params["selection_callback"]

	_rebuild_party_used_summons()
	if is_node_ready():
		_populate_espers_list()

func _ready() -> void:
	back_button.pressed.connect(func(): UIManager.pop())
	_rebuild_party_used_summons()
	_populate_espers_list()

func _populate_espers_list() -> void:
	for child in espers_list_container.get_children():
		child.queue_free()

	_maybe_add_remove_entry()

	var summons: Array = GameDatabase.get_all_esper()
	if summons.is_empty():
		_add_empty_state_label("No espers available.")
		return

	#var sorted_entries: Array[Dictionary] = []
	#for s in summons:
		#var summon_id: String = str(s.get("beastId"))
		#var summon_data: Variant = summons.get(summon_key, {})
		#if not (summon_data is Dictionary):
			#continue
#
		#sorted_entries.append({
			#"id": summon_id,
			#"sort_id": int(summon_id) if summon_id.is_valid_int() else 2147483647,
			#"data": summon_data
		#})
#
	#if sorted_entries.is_empty():
		#_add_empty_state_label("No espers available.")
		#return
#
	#sorted_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		#if a["sort_id"] == b["sort_id"]:
			#return String(a["id"]) < String(b["id"])
		#return int(a["sort_id"]) < int(b["sort_id"])
	#)

	for entry in summons:
		var summon_id: String = str(entry.get("beastId"))
		var summon_name: String = entry.get("esperName")
		var progression: Dictionary = EsperService.get_esper_progression(summon_id)
		var is_unlocked: bool = bool(progression.get("is_unlocked", false))

		# Skip locked espers
		if not is_unlocked:
			continue

		var frame: Button = esper_frame_template.duplicate()
		frame.visible = true
		var disabled_in_select_mode: bool = _is_summon_disabled_for_selection(summon_id)
		frame.disabled = disabled_in_select_mode
		frame.modulate = Color(1, 1, 1, 0.5) if disabled_in_select_mode else Color(1, 1, 1, 1)

		# Set name and level labels separately
		frame.get_node("NameLabel").text = summon_name
		var level: int = maxi(1, int(progression.get("level", 1)))
		if frame.has_node("LvlLabel"):
			frame.get_node("LvlLabel").text = "Lv. %d" % level
		if frame.has_node("SummonIcon"):
			var icon_filename: String = str(entry.get("thumImage", "")).strip_edges()
			var summon_icon: TextureRect = frame.get_node("SummonIcon")
			summon_icon.texture = null
			if icon_filename != "":
				var icon_path: String = "res://assets/esper/" + icon_filename
				if ResourceLoader.exists(icon_path):
					summon_icon.texture = ResourceLoader.load(icon_path) as Texture2D

		frame.pressed.connect(_on_esper_pressed.bind(summon_id, summon_name))
		espers_list_container.add_child(frame)

func _get_summon_display_name(summon_id: String, summon_data: Dictionary) -> String:
	var names_value: Variant = summon_data.get("names", [])
	if names_value is Array:
		var names_array: Array = names_value
		if names_array.size() > 0:
			var primary_name: String = str(names_array[0]).strip_edges()
			if primary_name != "":
				return primary_name
		for name_variant in names_array:
			var fallback_name: String = str(name_variant).strip_edges()
			if fallback_name != "":
				return fallback_name

	return "Summon %s" % summon_id

func _on_esper_pressed(summon_id: String, summon_name: String) -> void:
	if mode == "select":
		if _is_summon_disabled_for_selection(summon_id):
			return

		if selection_callback.is_valid():
			selection_callback.call(summon_id, summon_name)
		elif target_party_index >= 0 and target_slot_index >= 0:
			PartyService.assign_esper_to_party(target_party_index, target_slot_index, summon_id)

		UIManager.pop()
		return

	UIManager.push("esper_detail_ui", {
		"summon_id": summon_id,
		"summon_name": summon_name
	})

func _rebuild_party_used_summons() -> void:
	_party_used_summons.clear()
	if mode != "select":
		return
	if target_party_index < 0 or target_party_index >= PartyService.parties.size():
		return

	var party: Dictionary = PartyService.parties[target_party_index]
	var party_espers: Variant = party.get("espers", [])
	if not (party_espers is Array):
		return

	for summon_variant in party_espers:
		var summon_id: String = str(summon_variant).strip_edges()
		if summon_id == "":
			continue
		_party_used_summons[summon_id] = true

func _is_summon_disabled_for_selection(summon_id: String) -> bool:
	if mode != "select":
		return false
	if summon_id == "" or summon_id == current_summon_id:
		return false
	return _party_used_summons.has(summon_id)

func _maybe_add_remove_entry() -> void:
	if mode != "select":
		return
	if current_summon_id == "":
		return

	var frame: Button = esper_frame_template.duplicate()
	frame.visible = true
	frame.disabled = false
	frame.modulate = Color(1, 1, 1, 1)

	if frame.has_node("NameLabel"):
		frame.get_node("NameLabel").text = "Remove"
	if frame.has_node("LvlLabel"):
		frame.get_node("LvlLabel").visible = false
	if frame.has_node("SummonIcon"):
		frame.get_node("SummonIcon").visible = false
	if frame.has_node("RarityStar"):
		frame.get_node("RarityStar").visible = false

	frame.pressed.connect(_on_remove_pressed)
	espers_list_container.add_child(frame)

func _on_remove_pressed() -> void:
	if mode != "select":
		return

	if selection_callback.is_valid():
		selection_callback.call("", "")
	elif target_party_index >= 0 and target_slot_index >= 0:
		PartyService.assign_esper_to_party(target_party_index, target_slot_index, "")

	UIManager.pop()

func _add_empty_state_label(message: String) -> void:
	var empty_label := Label.new()
	empty_label.text = message
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	espers_list_container.add_child(empty_label)
