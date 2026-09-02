extends Control

@onready var back_button: TextureButton = $TopBar/UnitNamebgChara/BackButton

@onready var entry_window: Control = $EntryWindow
@onready var grade_texture: TextureRect = $EntryWindow/clsmVsCpu_grade
@onready var grade_label: Label = $EntryWindow/clsmVsCpu_grade/Label
@onready var rank_label: Label = $EntryWindow/clsmVsCpu_rank/Label
@onready var round_label: Label = $EntryWindow/clsmVsCpu_round/Label
@onready var progress_bar: TextureProgressBar = $EntryWindow/clsmVsCpu_rpgauge_bg/clsmVsCpu_rpgauge_bar
@onready var point_label: Label = $EntryWindow/clsmVsCpu_roundpoint_txt
@onready var remaining_point_label: Label = $EntryWindow/clsmVsCpu_roundclear_point_txt
@onready var entry_button: TextureButton = $EntryWindow/clsmVsCpu_entry_button

@onready var rank_selector: Control = $RankSelector

@onready var rank_containter: VBoxContainer = $RankSelector/ScrollContainer/VBoxContainer
@onready var rank_row: TextureButton = $RankSelector/ItemTemplate

@onready var round_selector: Control = $RoundSelector
@onready var round_containter: VBoxContainer = $RoundSelector/ScrollContainer/VBoxContainer
@onready var round_row: TextureButton = $RoundSelector/ItemTemplate

@onready var start_window: Control = $StartWindow
@onready var enemy_label: Label = $StartWindow/Header/clsmVsCpu_name_enemy_txt
@onready var party_label: Label = $StartWindow/Header/clsmVsCpu_name_player_txt
@onready var start_button: TextureButton = $StartWindow/clsmVsCpu_start_button
@onready var monster_names: Label = $StartWindow/MonsterNames
@onready var start_round_label: Label = $StartWindow/Header/clsmVsCpu_round_num_1/RoundLabel
@onready var enemies_container: Control = $StartWindow/Enemies

var ranks: Array = []
var rounds: Array = []

enum Depth { ENTRY, GRADE, RANK, ROUND, START }
var current_depth: Depth = Depth.ENTRY

var selected_grade = -1
var selected_rank = -1
var selected_round = -1
var progress

func _ready() -> void:
	init_scene({})

func init_scene(_params: Dictionary) -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	entry_button.pressed.connect(func():
		current_depth = Depth.RANK
		_refresh_list()
	)
	start_button.pressed.connect(_on_start_pressed)
	progress = ColosseumService.get_colosseum_progress()
	_refresh_list()


func _refresh_list() -> void:
	var current_items = []
	
	match current_depth:
		Depth.ENTRY:
			progress_bar.value = int(progress.get("points", 0))
			grade_label.text = progress.get("grade", "?")
			if ResourceLoader.exists("res://assets/ui/colosseum/colo_grade_%s.png" % progress.get("grade_id")):
				grade_texture.texture = ResourceLoader.load("res://assets/ui/colosseum/colo_grade_%s.png" % progress.get("grade_id")) as Texture2D
				grade_label.visible = false
			rank_label.text = progress.get("rank", "?")
			round_label.text = str(progress.get("roundId", "?"))[4]
			point_label.text = str(progress.get("points", "???"))
			remaining_point_label.text = str(1000 - progress.get("points", 0))
			entry_window.visible = true
			rank_selector.visible = false
			round_selector.visible = false
			start_window.visible = false
		Depth.GRADE:
			current_items = GameDatabase.get_clsm_available_grade(progress.get("roundId"))
			_populate_list(current_items)
		Depth.RANK:
			current_items = GameDatabase.get_clsm_available_rank(progress.get("roundId"))
			_populate_list(current_items)
			entry_window.visible = false
			rank_selector.visible = true
			round_selector.visible = false
			start_window.visible = false
		Depth.ROUND:
			current_items = GameDatabase.get_clsm_available_round(progress.get("roundId"))
			_populate_list(current_items)
			entry_window.visible = false
			rank_selector.visible = false
			round_selector.visible = true
			start_window.visible = false
		Depth.START:
			start_round_label.text = str(progress.get("roundId"))[4]
			var battle_data = ColosseumService.get_battle_info(selected_round)
			enemy_label.text = battle_data.get("name")
			var party_data = PartyService.get_active_party()
			party_label.text = party_data.get("name", "?")
			monster_names.text = ""
			for data in battle_data.get("battle_data"):
				var monster_data = GameDatabase.get_monster_parts(str(data.get("monsterId")))
				monster_names.text += monster_data.get("name") + "\n"
			entry_window.visible = false
			rank_selector.visible = false
			round_selector.visible = false
			start_window.visible = true
			
			
			for child in enemies_container.get_children():
				child.queue_free()
			
			# Enemy formation data
			var rows: Array = GameDatabase.get_battle_group(str(battle_data.get("battle_group_id")))

			for row in rows:
				var monster_id: String = str(row.get("monsterId", ""))
				if monster_id == "":
					continue
				
				var wrapper = Control.new()
				wrapper.custom_minimum_size = Vector2(140, 140)
				wrapper.size = Vector2(140, 140)
				wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
				var temp = row.get("dispPos").split(',')
				var enemy_disp_pos = Vector2(int(temp[0]), int(temp[1]))
				var region_size: Vector2 = enemies_container.size

				var half: Vector2 = Vector2(140, 140) * 0.5

				if enemy_disp_pos != Vector2.ZERO:
					var nx: float = clampf(enemy_disp_pos.x / Vector2(320, 480).x, 0.0, 1.0)
					var ny: float = clampf(enemy_disp_pos.y / Vector2(320, 480).y, 0.0, 1.0)
					wrapper.position =  Vector2(nx * region_size.x, ny * region_size.y) - half
				else:
					wrapper.position = Vector2.ZERO
				wrapper.position = _compute_enemy_wrapper_position(enemy_disp_pos)
				enemies_container.add_child(wrapper)

				var enemy_sprite = load("res://features/battle/ui/combat_sprite.gd").new()
				enemy_sprite.expand_mode = TextureRect.EXPAND_KEEP_SIZE
				enemy_sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
				enemy_sprite.set_anchors_preset(Control.PRESET_FULL_RECT)

				wrapper.add_child(enemy_sprite)
				enemy_sprite.setup(0, monster_id.left(-2), true, null)


func _populate_list(items: Array) -> void:
	for child in rank_containter.get_children():
		child.queue_free()
	for child in round_containter.get_children():
		child.queue_free()
	
	match current_depth:
		Depth.ENTRY:
			pass
		Depth.GRADE:
			pass
		Depth.RANK:
			for rank in items:
				var rank_node = rank_row.duplicate()
				var rank_name = rank_node.get_node("clsmVsCpu_rank_emblem/RankLabel")
				rank_name.text = rank.get("name")
				if rank.get("rankId") == progress.get("rankId"):
					var round_number = rank_node.get_node("clsmVsCpu_round_num_1/RoundLabel")
					round_number.text = str(progress.get("roundId"))[4]
				else:
					var rank_clear = rank_node.get_node("clsmVsCpu_clear_label")
					rank_clear.visible = true
				rank_node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				rank_node.visible = true
				rank_node.pressed.connect(_on_rank_selected.bind(rank.get("rankId")))
				rank_containter.add_child(rank_node)
		Depth.ROUND:
			for round in items:
				var round_node = round_row.duplicate()
				var round_name = round_node.get_node("clsmVsCpu_round_num/RoundLabel")
				round_name.text = str(round.get("roundId"))[4]
				if round.get("roundId") == progress.get("roundId"):
					var round_progress_bar = round_node.get_node("clsmVsCpu_rpgauge_bg/clsmVsCpu_rpgauge_bar")
					round_progress_bar.value = progress.get("points", 0)
					var round_point_label = round_node.get_node("clsmVsCpu_round_pt_txt")
					round_point_label.text = str(progress.get("points", 0))
					var round_remaining_point_label = round_node.get_node("clsmVsCpu_roundclear_pt_txt")
					round_remaining_point_label.text = str(1000 - progress.get("points", 0))
					if progress.get("points", 0) >= 1000:
						var boss_texture = round_node.get_node("clsmVsCpu_boss_appear")
						boss_texture.visible = true
				else:
					var round_clear = round_node.get_node("clsmVsCpu_clear_label")
					round_clear.visible = true
				round_node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				round_node.visible = true
				round_node.pressed.connect(_on_round_selected.bind(round.get("roundId")))
				round_containter.add_child(round_node)
		Depth.START:
			pass


func _on_grade_selected(grade: int) -> void:
	selected_grade = grade
	current_depth = Depth.GRADE
	_refresh_list()


func _on_rank_selected(rank: int) -> void:
	selected_rank = rank
	current_depth = Depth.ROUND
	_refresh_list()


func _on_round_selected(round: int) -> void:
	selected_round = round
	current_depth = Depth.START
	_refresh_list()


func _on_start_pressed() -> void:
	var battle_data = ColosseumService.start_colosseum(selected_round)
	progress = ColosseumService.get_colosseum_progress()
	UIManager.push("combat_ui", {"battle_group": battle_data.get("battle_group_id")})
	BattleEvents.mission_completed.connect(
		func(_a, _b):
			ColosseumService._on_colosseum_battle_finished(selected_round)
			progress = ColosseumService.get_colosseum_progress()
			_refresh_list()
			)


func _on_back_button_pressed() -> void:
	match current_depth:
		Depth.ENTRY:
			UIManager.pop()
		Depth.GRADE:
			pass
		Depth.RANK:
			current_depth = Depth.ENTRY
			selected_rank = -1
			_refresh_list()
		Depth.ROUND:
			current_depth = Depth.RANK
			selected_round = -1
			_refresh_list()
		Depth.START:
			current_depth = Depth.ROUND
			_refresh_list()






func _compute_enemy_wrapper_position(disp_pos: Vector2) -> Vector2:
	var region_size: Vector2 = enemies_container.size

	var half: Vector2 = Vector2(140, 140) * 0.5

	if disp_pos != Vector2.ZERO:
		var nx: float = clampf(disp_pos.x / Vector2(320, 480).x, 0.0, 1.0)
		var ny: float = clampf(disp_pos.y / Vector2(320, 480).y, 0.0, 1.0)
		return Vector2(nx * region_size.x, ny * region_size.y) - half
		
	return Vector2.ZERO
