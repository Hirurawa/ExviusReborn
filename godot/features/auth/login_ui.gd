extends Control

const INTRO_MISSION_ID: String = "1110100"
const ANDROID_PCK_PATH: String = "/storage/emulated/0/Android/data/com.hirurawa.exviusreborn/files/assets.pck"

# Persists across scene re-entry within the process: ProjectSettings.load_resource_pack
# mounts globally, so we only need to do it once per launch.
static var assets_mounted: bool = false

@onready var save_name_input: LineEdit = $VBoxContainer/EmailInput
@onready var save_select: OptionButton = $VBoxContainer/SaveSelect
@onready var password_input: LineEdit = $VBoxContainer/PasswordInput
@onready var feedback_label: Label = $VBoxContainer/FeedbackLabel
@onready var new_game_button: Button = $VBoxContainer/HBoxContainer/LoginButton
@onready var load_game_button: Button = $VBoxContainer/HBoxContainer/GoToRegisterButton

func _ready() -> void:
	# Reset memory trace file so each launch is fresh.
	var f: FileAccess = FileAccess.open("user://mem_trace.log", FileAccess.WRITE)
	if f:
		f.store_line("=== LoginUI _ready @ %s ===" % Time.get_datetime_string_from_system())
		f.close()

	password_input.hide()
	save_name_input.placeholder_text = "Save Name"
	save_name_input.text = ""
	save_select.item_selected.connect(_on_save_selected)
	new_game_button.text = "New Game"
	load_game_button.text = "Load Game"
	_refresh_save_dropdown()

	new_game_button.pressed.connect(_on_new_game_button_pressed)
	load_game_button.pressed.connect(_on_load_game_button_pressed)

	# On non-Android platforms, assets are bundled alongside the executable.
	if OS.get_name() != "Android":
		assets_mounted = true

	if assets_mounted:
		feedback_label.text = "Choose New Game or Load Game"
	else:
		_begin_android_mount_flow()

func _begin_android_mount_flow() -> void:
	# Fire-and-forget permission request; we'll surface a retry path if the
	# user denies or the file isn't present yet.
	OS.request_permissions()

	_set_buttons_enabled(false)
	feedback_label.text = "Mounting assets..."

	# Yield a frame so the permission dialog can render before we touch the FS.
	await get_tree().process_frame

	if await _try_mount_android_pck():
		_restore_normal_button_state()
	else:
		_show_retry_state()

func _try_mount_android_pck() -> bool:
	if assets_mounted:
		return true

	if not FileAccess.file_exists(ANDROID_PCK_PATH):
		feedback_label.text = "Assets not found. Place assets.pck at:\n%s" % ANDROID_PCK_PATH
		push_warning("Android PCK missing at %s" % ANDROID_PCK_PATH)
		return false

	var success: bool = ProjectSettings.load_resource_pack(ANDROID_PCK_PATH, true)
	if not success:
		feedback_label.text = "Found assets.pck but failed to mount it."
		push_warning("ProjectSettings.load_resource_pack failed for %s" % ANDROID_PCK_PATH)
		return false

	assets_mounted = true
	print("Successfully mounted Android PCK: %s" % ANDROID_PCK_PATH)
	return true

func _set_buttons_enabled(enabled: bool) -> void:
	new_game_button.disabled = not enabled
	load_game_button.disabled = not enabled

func _restore_normal_button_state() -> void:
	new_game_button.text = "New Game"
	load_game_button.text = "Load Game"
	_set_buttons_enabled(true)
	# Re-evaluate dropdown availability after mount.
	save_select.disabled = save_select.item_count <= 1
	feedback_label.text = "Choose New Game or Load Game"

func _show_retry_state() -> void:
	# Repurpose new_game_button as a Retry control until assets are mounted.
	new_game_button.text = "Retry Mount"
	new_game_button.disabled = false
	load_game_button.disabled = true
	save_select.disabled = true

func _on_retry_mount_pressed() -> void:
	# Routed through _on_new_game_button_pressed while in retry state.
	new_game_button.disabled = true
	feedback_label.text = "Retrying mount..."
	OS.request_permissions()
	await get_tree().process_frame
	if await _try_mount_android_pck():
		_restore_normal_button_state()
	else:
		_show_retry_state()

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
	_log_mem("new_game pressed")
	if not assets_mounted:
		await _on_retry_mount_pressed()
		return

	var save_name: String = save_name_input.text.strip_edges()
	if save_name.is_empty():
		feedback_label.text = "Save Name is required."
		return

	feedback_label.text = "Creating new game..."
	var result: Dictionary = await AccountService.start_new_local_game(save_name)
	_log_mem("after start_new_local_game")
	if not bool(result.get("success", false)):
		feedback_label.text = str(result.get("error_message", "Failed to create new game."))
		return

	_refresh_save_dropdown()

	feedback_label.text = "New game created!"
	_log_mem("before push game_ui")
	UIManager.push("game_ui")
	await get_tree().process_frame
	_log_mem("after push game_ui")

	var mission_result: Dictionary = await MissionService.request_start_mission(INTRO_MISSION_ID)
	_log_mem("after request_start_mission")
	if mission_result.get("success", false) == true:
		_log_mem("before push combat_ui")
		UIManager.push("combat_ui", {"mission_id": INTRO_MISSION_ID})
		await get_tree().process_frame
		_log_mem("after push combat_ui")
	else:
		push_warning("Intro mission failed to start after new game creation: %s" % mission_result.get("error", mission_result.get("error_message", "Unknown error")))

func _log_mem(tag: String) -> void:
	var static_mb: float = float(OS.get_static_memory_usage()) / 1048576.0
	var peak_mb: float = float(OS.get_static_memory_peak_usage()) / 1048576.0
	var line: String = "[MEM] %-32s static=%.1fMB peak=%.1fMB" % [tag, static_mb, peak_mb]
	print(line)
	# Persist to user:// so output survives a SIGABRT (Scudo OOM) where stdout
	# buffers may not flush to logcat.
	var f: FileAccess = FileAccess.open("user://mem_trace.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("user://mem_trace.log", FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("%s %s" % [Time.get_datetime_string_from_system(), line])
		f.close()

func _on_load_game_button_pressed() -> void:
	if not assets_mounted:
		feedback_label.text = "Assets not mounted yet."
		return

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
