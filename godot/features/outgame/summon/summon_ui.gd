extends Control

@onready var summon_perform_button: Button = $VBoxContainer/SummonButtonsRow/PerformSummonButton
@onready var summon_nv_perform_button: Button = $VBoxContainer/SummonButtonsRow/PerformNVSummonButton
@onready var get_cactuar_button: Button = $VBoxContainer/SummonButtonsRow/GetCactuarButton
@onready var get_moogle_button: Button = $VBoxContainer/SummonButtonsRow/GetMoogleButton
@onready var summon_overlay: ColorRect = $SummonOverlay
@onready var summon_results_list: GridContainer = $SummonOverlay/VBoxContainer/ScrollContainer/ResultsListContainer
@onready var summon_close_overlay_button: Button = $SummonOverlay/VBoxContainer/CloseOverlayButton

const UNIT_SCENE: PackedScene = preload("res://features/shared/Unit.tscn")

func _ready() -> void:
	summon_perform_button.pressed.connect(_on_summon_perform_button_pressed)
	summon_nv_perform_button.pressed.connect(_on_summon_nv_perform_button_pressed)
	get_cactuar_button.pressed.connect(_on_get_cactuar_button_pressed)
	get_moogle_button.pressed.connect(_on_get_moogle_button_pressed)
	summon_close_overlay_button.pressed.connect(func(): summon_overlay.hide())

func _on_summon_perform_button_pressed() -> void:
	var result: Dictionary = UnitService.summon_units(11)
	_show_summon_results(result)

func _on_summon_nv_perform_button_pressed() -> void:
	var result: Dictionary = UnitService.summon_units(11, true)
	_show_summon_results(result)

func _on_get_cactuar_button_pressed() -> void:
	var result: Dictionary = UnitService.summon_exp_boost_units(10)
	_show_summon_results(result)

func _on_get_moogle_button_pressed() -> void:
	var result: Dictionary = UnitService.summon_trust_units(10)
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
		var unit_data: Dictionary = unit_inst
		var unit_rarity: int = int(unit_inst.get("current_rarity", int(unit_data.get("rarity_min", 1))))
		var path = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_data.get("unitId")
		
		var container: VBoxContainer = VBoxContainer.new()
		if ResourceLoader.exists(path):
			#var unit_visual: Control = UNIT_SCENE.instantiate() as Control
			#unit_visual.scene_size = "small"
			#unit_visual.unit_data_to_load = unit_data
			#unit_visual.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
			#container.add_child(unit_visual)
			var sprite_texture = TextureRect.new()
			sprite_texture.texture = ResourceLoader.load(path) as Texture2D
			sprite_texture.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			container.add_child(sprite_texture)
		else:
			var name_label := Label.new()
			name_label.text = "%s (Rarity: %d★)" % [
				unit_data.get("unitName", "Unknown"),
				unit_rarity
			]
			name_label.add_theme_font_size_override("font_size", 18)
			container.add_child(name_label)

		summon_results_list.add_child(container)

	summon_overlay.show()
