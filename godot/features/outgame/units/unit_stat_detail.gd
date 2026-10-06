extends Control

@onready var overlay: ColorRect = $ColorRect

@onready var stats_container: HBoxContainer = $Stats
@onready var headers: HBoxContainer = $Header

var unit_instance: Dictionary
var stat_order: Array = ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]


func _ready() -> void:
	overlay.gui_input.connect(_on_overlay_gui_input)


func init_scene(params: Dictionary) -> void:
	if params.has("unit_instance"):
		unit_instance = params.unit_instance
	
	_populate_data()


func _populate_data() -> void:
	var unit_stats = unit_instance.get("final_stats")
	_add_header("res://assets/ui/unit/unit_status_label_total.tres")
	_add_stat_column(unit_stats.get("stats"))
	_add_header("")
	_add_stat_column(unit_stats.get("base_stats"))
	_add_header("res://assets/ui/unit/unit_status_label_equipetc.tres")
	_add_stat_column(unit_stats.get("equipment_stats"))
	_add_header("Esper")
	_add_stat_column(unit_stats.get("esper_stats"))


func _add_stat_column(item: Dictionary) -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for stat_name in stat_order:
		col.name = stat_name
		var label = Label.new()
		label.text = str(item.get(stat_name))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		col.add_child(label)
	
	stats_container.add_child(col)


func _add_header(header_name: String) -> void:
	var header_texture
	if ResourceLoader.exists(header_name):
		header_texture = TextureRect.new()
		header_texture.texture = ResourceLoader.load(header_name)
		header_texture.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	else:
		header_texture = Label.new()
		header_texture.text = header_name
		header_texture.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_texture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headers.add_child(header_texture)


func _on_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		queue_free()
