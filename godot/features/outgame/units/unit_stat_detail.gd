extends Control

@onready var overlay: ColorRect = $ColorRect

@onready var stats_container: HBoxContainer = $Stats
@onready var headers: HBoxContainer = $Header

var unit_instance: Dictionary
var stat_order: Array = ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]

## The passive percent beside a Passive value.
const PERCENT_FONT_SIZE: int = 12
const PERCENT_GAP: int = 2
const PERCENT_COLOR: Color = Color(0.7, 0.78, 0.9)
## A percent past StatCalculator.MAX_STAT_PCT_BONUS: the excess adds nothing.
const PERCENT_CAPPED_COLOR: Color = Color(1.0, 0.55, 0.35)
## The Passive column is wider than the rest to fit the percent; its header gets the same
## ratio so the two rows stay aligned.
const PASSIVE_COLUMN_RATIO: float = 1.4


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
	_add_header("Base")
	_add_stat_column(unit_stats.get("base_stats"))
	_add_header("res://assets/ui/unit/unit_status_label_equipetc.tres")
	_add_stat_column(unit_stats.get("equipment_stats"))
	# Doublehand, true doublehand, dual wield, single weapon and unarmed boosts to the
	# equipment's stats.
	_add_header("TDH/TDW")
	_add_stat_column(unit_stats.get("equipment_bonus"))
	_add_header("Passive", PASSIVE_COLUMN_RATIO)
	_add_stat_column(unit_stats.get("passive_stats"), unit_stats.get("passive_pct", {}), PASSIVE_COLUMN_RATIO)
	_add_header("Esper")
	_add_stat_column(unit_stats.get("esper_stats"))


## `percents`, when given, puts each stat's percent after its value in a smaller font
## (none for 0), colored when it is past the cap the value is computed with.
func _add_stat_column(item: Dictionary, percents: Dictionary = {}, stretch_ratio: float = 1.0) -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = stretch_ratio
	for stat_name in stat_order:
		col.name = stat_name
		var label = Label.new()
		label.text = str(item.get(stat_name))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var pct: int = int(percents.get(stat_name, 0))
		if pct == 0:
			col.add_child(label)
			continue
		var cell: HBoxContainer = HBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_END
		cell.add_theme_constant_override("separation", PERCENT_GAP)
		cell.add_child(label)
		var pct_label: Label = Label.new()
		pct_label.text = "(%+d%%)" % pct
		pct_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		pct_label.add_theme_font_size_override("font_size", PERCENT_FONT_SIZE)
		var capped: bool = pct > StatCalculator.MAX_STAT_PCT_BONUS
		pct_label.add_theme_color_override("font_color", PERCENT_CAPPED_COLOR if capped else PERCENT_COLOR)
		cell.add_child(pct_label)
		col.add_child(cell)

	stats_container.add_child(col)


func _add_header(header_name: String, stretch_ratio: float = 1.0) -> void:
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
	header_texture.size_flags_stretch_ratio = stretch_ratio
	headers.add_child(header_texture)


func _on_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		queue_free()
