extends Control

@onready var summon_perform_button = $VBoxContainer/PerformSummonButton
@onready var summon_overlay = $SummonOverlay
@onready var summon_results_list = $SummonOverlay/VBoxContainer/ScrollContainer/ResultsListContainer
@onready var summon_close_overlay_button = $SummonOverlay/VBoxContainer/CloseOverlayButton

func _ready():
	summon_perform_button.pressed.connect(_on_summon_perform_button_pressed)
	summon_close_overlay_button.pressed.connect(func(): summon_overlay.hide())

func _on_summon_perform_button_pressed() -> void:
	if DataManager.game_data_units.is_empty():
		return

	var summoned_units = await DataManager.summon_units(3)

	for child in summon_results_list.get_children():
		child.queue_free()

	for unit_inst in summoned_units:
		var unit_id = unit_inst.get("unit_id", "")
		var unit_data: Dictionary = DataManager.game_data_units.get(unit_id, {})
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label := Label.new()
		name_label.text = "%s (Rarity: %d★)" % [
			unit_data.get("name", "Unknown"),
			unit_inst.get("current_rarity", 1)
		]
		name_label.add_theme_font_size_override("font_size", 18)
		vbox.add_child(name_label)

		var separator := HSeparator.new()
		vbox.add_child(separator)

		summon_results_list.add_child(vbox)

	summon_overlay.show()
