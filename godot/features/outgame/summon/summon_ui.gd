extends Control

@onready var summon_perform_button: Button = $VBoxContainer/SummonButtonsRow/PerformSummonButton
@onready var get_cactuar_button: Button = $VBoxContainer/SummonButtonsRow/GetCactuarButton
@onready var get_moogle_button: Button = $VBoxContainer/SummonButtonsRow/GetMoogleButton
@onready var summon_overlay: ColorRect = $SummonOverlay
@onready var summon_results_list: VBoxContainer = $SummonOverlay/VBoxContainer/ScrollContainer/ResultsListContainer
@onready var summon_close_overlay_button: Button = $SummonOverlay/VBoxContainer/CloseOverlayButton

func _ready() -> void:
	summon_perform_button.pressed.connect(_on_summon_perform_button_pressed)
	get_cactuar_button.pressed.connect(_on_get_cactuar_button_pressed)
	get_moogle_button.pressed.connect(_on_get_moogle_button_pressed)
	summon_close_overlay_button.pressed.connect(func(): summon_overlay.hide())

func _on_summon_perform_button_pressed() -> void:
	if StaticData.game_data_units.is_empty():
		return

	var result: Dictionary = await UnitService.summon_units(3)
	_show_summon_results(result)

func _on_get_cactuar_button_pressed() -> void:
	if StaticData.game_data_units.is_empty():
		return

	var result: Dictionary = await UnitService.summon_exp_boost_units(3)
	_show_summon_results(result)

func _on_get_moogle_button_pressed() -> void:
	if StaticData.game_data_units.is_empty():
		return

	var result: Dictionary = await UnitService.summon_trust_units(3)
	_show_summon_results(result)

func _show_summon_results(result: Dictionary) -> void:
	for child in summon_results_list.get_children():
		child.queue_free()

	if result.has("error"):
		var error_label := Label.new()
		error_label.text = result["error"]
		error_label.add_theme_font_size_override("font_size", 18)
		summon_results_list.add_child(error_label)
		summon_overlay.show()
		return

	var summoned_units: Array = result.get("summoned", [])
	if summoned_units.is_empty():
		return

	for unit_inst in summoned_units:
		var unit_id: String = unit_inst.get("unit_id", "")
		var unit_data: Dictionary = StaticData.game_data_units.get(unit_id, {})
		var unit_rarity: int = int(unit_inst.get("current_rarity", int(unit_data.get("rarity_min", 1))))
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label := Label.new()
		name_label.text = "%s (Rarity: %d★)" % [
			unit_data.get("name", "Unknown"),
			unit_rarity
		]
		name_label.add_theme_font_size_override("font_size", 18)
		vbox.add_child(name_label)

		var separator := HSeparator.new()
		vbox.add_child(separator)

		summon_results_list.add_child(vbox)

	summon_overlay.show()
