extends Control

const INTRO_MISSION_ID: String = "1110100"

@onready var save_name_input: LineEdit = $VBoxContainer/EmailInput
@onready var save_select: OptionButton = $VBoxContainer/SaveSelect
@onready var password_input: LineEdit = $VBoxContainer/PasswordInput
@onready var feedback_label: Label = $VBoxContainer/FeedbackLabel
@onready var new_game_button: Button = $VBoxContainer/HBoxContainer/LoginButton
@onready var load_game_button: Button = $VBoxContainer/HBoxContainer/GoToRegisterButton

func _ready() -> void:
	password_input.hide()
	feedback_label.text = "Choose New Game or Load Game"
	save_name_input.placeholder_text = "Save Name"
	save_name_input.text = ""
	save_select.item_selected.connect(_on_save_selected)
	new_game_button.text = "New Game"
	load_game_button.text = "Load Game"
	_refresh_save_dropdown()

	new_game_button.pressed.connect(_on_new_game_button_pressed)
	load_game_button.pressed.connect(_on_load_game_button_pressed)

func _refresh_save_dropdown() -> void:
	save_select.clear()
	save_select.add_item("Select existing save...")
	save_select.set_item_metadata(0, "")

	var local_saves: Array = AccountService.list_local_saves()
	for save_var in local_saves:
		if not (save_var is Dictionary):
			continue
		var save_entry: Dictionary = save_var
		var save_name: String = str(save_entry.get("username", "")).strip_edges()
		if save_name == "":
			continue
		save_select.add_item(save_name)
		save_select.set_item_metadata(save_select.item_count - 1, save_name)

	save_select.selected = 0
	save_select.disabled = save_select.item_count <= 1

func _on_save_selected(index: int) -> void:
	if index < 0 or index >= save_select.item_count:
		return

	var selected_save: String = str(save_select.get_item_metadata(index)).strip_edges()
	if selected_save != "":
		save_name_input.text = selected_save

func _on_new_game_button_pressed() -> void:
	var save_name: String = save_name_input.text.strip_edges()
	if save_name.is_empty():
		feedback_label.text = "Save Name is required."
		return

	feedback_label.text = "Creating new game..."
	var result: Dictionary = await AccountService.start_new_local_game(save_name)
	if not bool(result.get("success", false)):
		feedback_label.text = str(result.get("error_message", "Failed to create new game."))
		return

	_refresh_save_dropdown()

	feedback_label.text = "New game created!"
	UIManager.push("game_ui")

	var mission_result: Dictionary = await MissionService.request_start_mission(INTRO_MISSION_ID)
	if mission_result.get("success", false) == true:
		UIManager.push("combat_ui", {"mission_id": INTRO_MISSION_ID})
	else:
		push_warning("Intro mission failed to start after new game creation: %s" % mission_result.get("error", mission_result.get("error_message", "Unknown error")))

func _on_load_game_button_pressed() -> void:
	var save_name: String = save_name_input.text.strip_edges()
	if save_name == "" and save_select.selected > 0 and save_select.selected < save_select.item_count:
		save_name = str(save_select.get_item_metadata(save_select.selected)).strip_edges()
	if save_name.is_empty():
		feedback_label.text = "Save Name is required."
		return

	feedback_label.text = "Loading game..."
	var result: Dictionary = await AccountService.load_local_game(save_name)
	if not bool(result.get("success", false)):
		feedback_label.text = str(result.get("error_message", "Failed to load game."))
		return

	feedback_label.text = "Game loaded!"
	UIManager.push("game_ui")
