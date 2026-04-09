extends Control

var current_mission_id: String = ""

@onready var monsters_list = %MonstersList
@onready var finish_button = %FinishButton
@onready var rewards_popup = %RewardsPopup

func _ready() -> void:
	finish_button.pressed.connect(_on_finish_pressed)
	rewards_popup.confirmed.connect(_on_rewards_confirmed)

func init_scene(params: Dictionary) -> void:
	current_mission_id = params.get("mission_id", "")
	var dungeon_id = params.get("dungeon_id", "")

	_populate_monsters(dungeon_id)

func _populate_monsters(dungeon_id: String) -> void:
	# Clear existing children
	for child in monsters_list.get_children():
		child.queue_free()

	var dungeon_data = DataManager.game_data_dungeons.get(dungeon_id, {})
	var monsters_in_dungeon = dungeon_data.get("monsters", [])

	if monsters_in_dungeon.size() == 0:
		var empty_lbl = Label.new()
		empty_lbl.text = "No monsters encountered."
		monsters_list.add_child(empty_lbl)
		return

	for dungeon_monster in monsters_in_dungeon:
		var m_name = dungeon_monster.get("name", "Unknown Monster")

		# Find the monster in the cached monsters array by name to get extra details
		var extra_details = {}
		# game_data_monsters is an Array of Dictionaries
		var monsters_array = DataManager.game_data_monsters
		if typeof(monsters_array) == TYPE_ARRAY:
			for m in monsters_array:
				if typeof(m) == TYPE_DICTIONARY and m.get("name") == m_name:
					extra_details = m
					break
		elif typeof(monsters_array) == TYPE_DICTIONARY:
			# fallback just in case
			extra_details = monsters_array.get(m_name)

		var vbox = VBoxContainer.new()
		var pnl = PanelContainer.new()

		var inner_vbox = VBoxContainer.new()
		pnl.add_child(inner_vbox)

		var name_lbl = Label.new()
		name_lbl.text = m_name
		if extra_details.has("race"):
			name_lbl.text += " (%s)" % extra_details.get("race", "Unknown")
		name_lbl.add_theme_font_size_override("font_size", 20)
		inner_vbox.add_child(name_lbl)

		var stats_lbl = Label.new()
		stats_lbl.text = "Lv: %s | HP: %s | MP: %s | EXP: %s | Gil: %s" % [
			str(int(dungeon_monster.get("level", "?"))),
			str(int(dungeon_monster.get("hp", "?"))),
			str(int(dungeon_monster.get("mp", "?"))),
			str(int(dungeon_monster.get("exp", "?"))),
			str(int(dungeon_monster.get("gil", "?")))
		]
		inner_vbox.add_child(stats_lbl)

		#if extra_details.has("description"):
			#var desc_lbl = Label.new()
			#desc_lbl.text = str(extra_details.get("description", ""))
			#desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			#desc_lbl.add_theme_font_size_override("font_size", 12)
			#inner_vbox.add_child(desc_lbl)

		if extra_details.has("resistances"):
			var res_lbl = Label.new()
			res_lbl.text = str(extra_details.get("resistances", ""))
			res_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			res_lbl.add_theme_font_size_override("font_size", 12)
			inner_vbox.add_child(res_lbl)

		vbox.add_child(pnl)

		var sep = HSeparator.new()
		vbox.add_child(sep)

		monsters_list.add_child(vbox)

func _on_finish_pressed() -> void:
	if current_mission_id == "":
		return

	finish_button.disabled = true
	var result = await DataManager.perform_mission(current_mission_id)

	if result.has("error"):
		print("Failed to complete mission: ", result.error)
		finish_button.disabled = false
	else:
		# Success! Show rewards popup
		rewards_popup.dialog_text = "Mission completed successfully!\n"

		var rewards_text = ""

		# Show Gil/Lapis rewards if any from wallet changes (simplified for placeholder)
		var mission_data = DataManager.game_data_missions.get(current_mission_id, {})
		if mission_data.has("gil"):
			rewards_text += "Gil +%s\n" % str(int(mission_data.get("gil", 0)))
		if mission_data.has("exp"):
			rewards_text += "Rank EXP +%s\n" % str(int(mission_data.get("exp", 0)))

		rewards_popup.dialog_text += rewards_text
		rewards_popup.popup_centered()

func _on_rewards_confirmed() -> void:
	UIManager.pop()
