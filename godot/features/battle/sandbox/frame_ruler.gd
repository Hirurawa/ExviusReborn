extends Control

## Draws a FrameRulerModel: frames run left to right with the current frame marked,
## one row per target. Filled marks have landed, hollow ones are pending, crosses are
## misses, dots are hits that do not chain (heals, statuses). Each damage hit trails a
## bar as long as the chain window: a hit that starts inside the previous hit's bar,
## from another source, continues the chain. Hover a mark for its details.

const LABEL_WIDTH: float = 110.0
const LEGEND_HEIGHT: float = 18.0
const SCALE_HEIGHT: float = 16.0
const ROW_HEIGHT: float = 24.0
const RIGHT_PAD: float = 8.0
const FONT_SIZE: int = 12
const SMALL_FONT_SIZE: int = 10
const HOVER_DISTANCE: float = 5.0

const BACKGROUND := Color(0.09, 0.09, 0.11)
const GRID := Color(1, 1, 1, 0.06)
const GRID_STRONG := Color(1, 1, 1, 0.14)
const NOW_LINE := Color(1.0, 0.85, 0.3)
const TEXT := Color(0.85, 0.85, 0.9)
const MUTED := Color(0.55, 0.55, 0.6)
const ACTOR_COLORS: Array[Color] = [
	Color(0.35, 0.7, 1.0), Color(1.0, 0.55, 0.3), Color(0.5, 0.9, 0.45), Color(0.95, 0.4, 0.75),
	Color(0.95, 0.9, 0.35), Color(0.6, 0.5, 1.0), Color(0.3, 0.9, 0.85), Color(0.9, 0.35, 0.35),
]

var model: FrameRulerModel = null
var engine: BattleEngine = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func show_model(new_model: FrameRulerModel, battle_engine: BattleEngine) -> void:
	model = new_model
	engine = battle_engine
	var row_count: int = model.rows.size() if model != null else 1
	custom_minimum_size.y = LEGEND_HEIGHT + SCALE_HEIGHT + ROW_HEIGHT * maxi(1, row_count) + 4.0
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	var font: Font = get_theme_default_font()
	if model == null or engine == null:
		draw_string(font, Vector2(8, 20), "No battle", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
		return
	_draw_legend(font)
	_draw_scale(font)
	for i in range(model.rows.size()):
		_draw_row(font, model.rows[i], LEGEND_HEIGHT + SCALE_HEIGHT + ROW_HEIGHT * i)


func _get_tooltip(at_position: Vector2) -> String:
	if model == null or engine == null:
		return ""
	var row_index: int = floori((at_position.y - LEGEND_HEIGHT - SCALE_HEIGHT) / ROW_HEIGHT)
	if row_index < 0 or row_index >= model.rows.size():
		return ""
	var best: FrameRulerModel.Mark = null
	var best_distance: float = HOVER_DISTANCE
	for mark in model.rows[row_index].marks:
		var distance: float = absf(_x(mark.frame) - at_position.x)
		if distance <= best_distance:
			best = mark
			best_distance = distance
	return model.describe(best, engine) if best != null else ""


func _draw_legend(font: Font) -> void:
	var x: float = 8.0
	draw_string(font, Vector2(x, 13), "f%d" % model.now, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, NOW_LINE)
	x = LABEL_WIDTH
	for actor_id in model.actors:
		var fighter: Combatant = engine.combatant(actor_id)
		var label: String = "%s#%d" % [fighter.name, actor_id] if fighter != null else str(actor_id)
		draw_rect(Rect2(x, 4, 10, 10), _actor_color(actor_id))
		draw_string(font, Vector2(x + 14, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
		x += 24.0 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		if x > size.x - 60.0:
			break


func _draw_scale(font: Font) -> void:
	var top: float = LEGEND_HEIGHT
	var bottom: float = size.y
	var start: int = model.first_frame - posmod(model.first_frame - model.now, 10)
	for frame in range(start, model.last_frame + 1, 10):
		if frame < model.first_frame:
			continue
		var x: float = _x(frame)
		var offset: int = frame - model.now
		var strong: bool = offset % 30 == 0
		draw_line(Vector2(x, top + SCALE_HEIGHT - 4), Vector2(x, bottom), GRID_STRONG if strong else GRID)
		if strong and x < size.x - 30.0:
			var text: String = "now" if offset == 0 else "%+d" % offset
			draw_string(font, Vector2(x + 2, top + 11), text, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_FONT_SIZE, MUTED)
	var now_x: float = _x(model.now)
	draw_line(Vector2(now_x, top), Vector2(now_x, bottom), NOW_LINE, 2.0)


func _draw_row(font: Font, row: FrameRulerModel.Row, top: float) -> void:
	var fighter: Combatant = engine.combatant(row.target_id)
	var label: String = row.label
	if fighter != null and fighter.chain_count > 0:
		label += "  c%d" % fighter.chain_count
	draw_line(Vector2(0, top), Vector2(size.x, top), GRID)
	draw_string(font, Vector2(6, top + 16), label, HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 10, FONT_SIZE, TEXT)
	var mid: float = top + ROW_HEIGHT * 0.5
	var track_end: float = size.x - RIGHT_PAD
	# Chain windows first, so marks draw over them.
	for mark in row.marks:
		if mark.damage and not mark.missed:
			var from: float = _x(mark.frame)
			var to: float = minf(_x(mark.frame + model.chain_window), track_end)
			if to > LABEL_WIDTH:
				var color: Color = _actor_color(mark.actor_id)
				color.a = 0.22
				draw_rect(Rect2(maxf(from, LABEL_WIDTH), mid + 3, to - maxf(from, LABEL_WIDTH), 5), color)
	for mark in row.marks:
		var x: float = _x(mark.frame)
		if x < LABEL_WIDTH or x > track_end:
			continue
		var color: Color = _actor_color(mark.actor_id)
		if mark.missed:
			draw_line(Vector2(x - 3, mid - 6), Vector2(x + 3, mid), MUTED, 1.5)
			draw_line(Vector2(x - 3, mid), Vector2(x + 3, mid - 6), MUTED, 1.5)
		elif not mark.damage:
			draw_circle(Vector2(x, mid - 3), 3.0, color if not mark.pending else color.darkened(0.4))
		elif mark.pending:
			draw_rect(Rect2(x - 1.5, mid - 9, 3, 12), color, false, 1.0)
		else:
			draw_rect(Rect2(x - 1.5, mid - 9, 3, 12), color)
			if mark.chain > 0:
				draw_string(font, Vector2(x + 2, mid - 3), str(mark.chain), HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_FONT_SIZE, TEXT)


func _x(frame: int) -> float:
	var width: float = maxf(1.0, size.x - LABEL_WIDTH - RIGHT_PAD)
	return LABEL_WIDTH + model.position_of(frame) * width


func _actor_color(actor_id: int) -> Color:
	return ACTOR_COLORS[posmod(actor_id, ACTOR_COLORS.size())]
