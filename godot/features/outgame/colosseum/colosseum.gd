extends Control

@onready var back_button: TextureButton = $TopBar/UnitNamebgChara/BackButton

@onready var entry_window: Control = $EntryWindow
@onready var entry_button: TextureButton = $EntryWindow/clsmVsCpu_entry_button

@onready var rank_selector: Control = $RankSelector
@onready var rank_containter: VBoxContainer = $RankSelector/ScrollContainer/VBoxContainer
@onready var rank_row: TextureButton = $RankSelector/ItemTemplate

@onready var round_selector: Control = $RoundSelector
@onready var round_containter: VBoxContainer = $RoundSelector/ScrollContainer/VBoxContainer
@onready var round_row: TextureButton = $RoundSelector/ItemTemplate

@onready var start_window: Control = $StartWindow
@onready var enemy_label: Label = $StartWindow/Header/clsmVsCpu_name_enemy_txt
@onready var start_button: TextureButton = $StartWindow/clsmVsCpu_start_button
@onready var monster_names: Label = $StartWindow/MonsterNames

var ranks: Array = []
var rounds: Array = []

enum Depth { ENTRY, RANK, ROUND, START }
var current_depth: Depth = Depth.ENTRY

var selected_rank = -1
var selected_round = -1

func _ready() -> void:
	init_scene({})

func init_scene(_params: Dictionary) -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	entry_button.pressed.connect(func():
		current_depth = Depth.RANK
		_refresh_list()
	)
	start_button.pressed.connect(_on_start_pressed)
	_refresh_list()


func _refresh_list() -> void:
	var current_items = []
	
	match current_depth:
		Depth.ENTRY:
			entry_window.visible = true
			rank_selector.visible = false
			round_selector.visible = false
			start_window.visible = false
		Depth.RANK:
			current_items = GameDatabase.get_clsm_rank()
			_populate_list(current_items)
			entry_window.visible = false
			rank_selector.visible = true
			round_selector.visible = false
			start_window.visible = false
		Depth.ROUND:
			current_items = GameDatabase.get_clsm_round(1, selected_rank)
			_populate_list(current_items)
			entry_window.visible = false
			rank_selector.visible = false
			round_selector.visible = true
			start_window.visible = false
		Depth.START:
			var battle_groups = GameDatabase.get_clsm_monster_group(selected_round)
			enemy_label.text = battle_groups[0].get("name")
			var random_battle_group = battle_groups.pick_random()
			var battle_data = GameDatabase.get_battle_group(str(random_battle_group.get("battleGroupId")))
			for data in battle_data:
				var monster_data = GameDatabase.get_monster_parts(str(data.get("monsterId")))
				monster_names.text += monster_data.get("name") + "\n"
			entry_window.visible = false
			rank_selector.visible = false
			round_selector.visible = false
			start_window.visible = true


func _populate_list(items: Array) -> void:
	for child in rank_containter.get_children():
		child.queue_free()
	for child in round_containter.get_children():
		child.queue_free()
	
	match current_depth:
		Depth.ENTRY:
			pass
		Depth.RANK:
			for rank in items:
				var rank_node = rank_row.duplicate()
				var rank_name = rank_node.get_node("clsmVsCpu_rank_emblem/RankLabel")
				rank_name.text = rank.get("name")
				rank_node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				rank_node.visible = true
				rank_node.pressed.connect(_on_rank_selected.bind(rank.get("rankId")))
				rank_containter.add_child(rank_node)
		Depth.ROUND:
			for round in items:
				var round_node = round_row.duplicate()
				var round_name = round_node.get_node("clsmVsCpu_round_num/RoundLabel")
				round_name.text = round.get("name")
				round_node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				round_node.visible = true
				round_node.pressed.connect(_on_round_selected.bind(round.get("roundId")))
				round_containter.add_child(round_node)
		Depth.START:
			pass


func _on_rank_selected(rank: int) -> void:
	selected_rank = rank
	current_depth = Depth.ROUND
	_refresh_list()


func _on_round_selected(round: int) -> void:
	selected_round = round
	current_depth = Depth.START
	_refresh_list()


func _on_start_pressed() -> void:
	print("START COLOSSEUM")


func _on_back_button_pressed() -> void:
	match current_depth:
		Depth.ENTRY:
			UIManager.pop()
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
			monster_names.text = ""
			_refresh_list()
