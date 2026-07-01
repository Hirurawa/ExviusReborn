extends Control

const INTRO_MISSION_ID: String = "1110100"
const ANDROID_PCK_PATH: String = "/storage/emulated/0/Android/data/com.hirurawa.exviusreborn/files/assets.pck"

# Persists across scene re-entry within the process: ProjectSettings.load_resource_pack
# mounts globally, so we only need to do it once per launch.
static var assets_mounted: bool = false

@onready var feedback_label: Label = $VBoxContainer/FeedbackLabel
@onready var continue_button: Button = $VBoxContainer/ContinueButton
@onready var new_game_button: Button = $VBoxContainer/NewGameButton
@onready var load_game_button: Button = $VBoxContainer/LoadGameButton
@onready var new_game_dialog: AcceptDialog = $NewGameDialog
@onready var load_game_dialog: PopupPanel = $LoadGameDialog
@onready var delete_confirm_dialog: ConfirmationDialog = $DeleteConfirmDialog

var _continue_username: String = ""
var _pending_delete_save_id: String = ""
var _pending_delete_username: String = ""


func _ready() -> void:
	# Reset memory trace file so each launch is fresh (debug builds only).
	if OS.is_debug_build():
		var f: FileAccess = FileAccess.open("user://mem_trace.log", FileAccess.WRITE)
		if f:
			f.store_line("=== LoginUI _ready @ %s ===" % Time.get_datetime_string_from_system())
			f.close()

	continue_button.pressed.connect(_on_continue_button_pressed)
	new_game_button.pressed.connect(_on_new_game_button_pressed)
	load_game_button.pressed.connect(_on_load_game_button_pressed)

	new_game_dialog.created.connect(_on_new_game_created)
	load_game_dialog.load_selected.connect(_on_load_selected)
	load_game_dialog.delete_requested.connect(_on_delete_requested)
	delete_confirm_dialog.confirmed.connect(_on_delete_confirmed)

	# On non-Android platforms, assets are bundled alongside the executable.
	if OS.get_name() != "Android":
		assets_mounted = true

	# Surface cold-path progress so the player sees forward motion instead of a
	# freeze on first launch (signature mismatch).
	if not StaticDataLoader.patch_progress.is_connected(_on_static_data_progress):
		StaticDataLoader.patch_progress.connect(_on_static_data_progress)

	if assets_mounted:
		_refresh_continue_button()
		feedback_label.text = "Choose an option"
		_kick_off_priming()
	else:
		_begin_android_mount_flow()


# === Android asset mount flow ===

func _begin_android_mount_flow() -> void:
	OS.request_permissions()
	_set_buttons_enabled(false)
	feedback_label.text = "Mounting assets..."

	await get_tree().process_frame

	if await _try_mount_android_pck():
		_restore_normal_button_state()
		_kick_off_priming()
	else:
		_show_retry_state()


func _try_mount_android_pck() -> bool:
	if assets_mounted:
		return true

	if not FileAccess.file_exists(ANDROID_PCK_PATH):
		feedback_label.text = "Assets not found. Place assets.pck at:\n%s" % ANDROID_PCK_PATH
		Log.warn("Android PCK missing at %s" % ANDROID_PCK_PATH, "LoginUI")
		return false

	# The bundled database must be copied from the APK to user:// *before* the PCK
	# is mounted, otherwise Godot's FileAccess fails to read the overridden res:// file.
	GameDatabase.preload_database()

	var success: bool = ProjectSettings.load_resource_pack(ANDROID_PCK_PATH, true)
	if not success:
		feedback_label.text = "Found assets.pck but failed to mount it."
		Log.warn("ProjectSettings.load_resource_pack failed for %s" % ANDROID_PCK_PATH, "LoginUI")
		return false

	assets_mounted = true
	Log.info("Successfully mounted Android PCK: %s" % ANDROID_PCK_PATH, "LoginUI")
	return true


func _set_buttons_enabled(enabled: bool) -> void:
	new_game_button.disabled = not enabled
	load_game_button.disabled = not enabled
	continue_button.disabled = not enabled or _continue_username == ""


func _restore_normal_button_state() -> void:
	new_game_button.text = "New Game"
	load_game_button.text = "Load Game"
	new_game_button.disabled = false
	load_game_button.disabled = false
	_refresh_continue_button()
	feedback_label.text = "Choose an option"


func _show_retry_state() -> void:
	# Repurpose new_game_button as a Retry control until assets are mounted.
	new_game_button.text = "Retry Mount"
	new_game_button.disabled = false
	load_game_button.disabled = true
	continue_button.disabled = true


func _on_retry_mount_pressed() -> void:
	new_game_button.disabled = true
	feedback_label.text = "Retrying mount..."
	OS.request_permissions()
	await get_tree().process_frame
	if await _try_mount_android_pck():
		_restore_normal_button_state()
		_kick_off_priming()
	else:
		_show_retry_state()


# === Continue ===

func _refresh_continue_button() -> void:
	var entry: Dictionary = AccountService.get_continue_save()
	_continue_username = str(entry.get("username", "")).strip_edges()
	if _continue_username == "":
		continue_button.disabled = true
		continue_button.text = "Continue"
	else:
		continue_button.disabled = false
		continue_button.text = "Continue (%s)" % _continue_username


func _on_continue_button_pressed() -> void:
	if not assets_mounted:
		feedback_label.text = "Assets not mounted yet."
		return
	if _continue_username == "":
		feedback_label.text = "No save to continue."
		return
	await _load_and_enter(_continue_username)


# === New Game ===

func _on_new_game_button_pressed() -> void:
	_log_mem("new_game pressed")
	if not assets_mounted:
		await _on_retry_mount_pressed()
		return
	new_game_dialog.popup_centered()


func _on_new_game_created(username: String) -> void:
	_log_mem("after start_new_local_game")
	_refresh_continue_button()
	feedback_label.text = "New game created!"
	_log_mem("before push game_ui")
	UIManager.push("game_ui")
	await get_tree().process_frame
	_log_mem("after push game_ui")

	var mission_result: Dictionary = MissionService.request_start_mission(INTRO_MISSION_ID)
	_log_mem("after request_start_mission")
	if mission_result.get("success", false) == true:
		_log_mem("before push combat_ui")

		UIManager.push("combat_ui", {"mission_id": INTRO_MISSION_ID})
		await get_tree().process_frame
		_log_mem("after push combat_ui")
	else:
		Log.warn("Intro mission failed to start after new game creation: %s" % mission_result.get("error", mission_result.get("error_message", "Unknown error")), "LoginUI")


# === Load Game ===

func _on_load_game_button_pressed() -> void:
	if not assets_mounted:
		feedback_label.text = "Assets not mounted yet."
		return
	load_game_dialog.refresh()
	load_game_dialog.popup_centered()


func _on_load_selected(username: String) -> void:
	await _load_and_enter(username)


func _load_and_enter(username: String) -> void:
	feedback_label.text = "Loading game..."
	var result: Dictionary = await AccountService.load_local_game(username)
	if not bool(result.get("success", false)):
		feedback_label.text = str(result.get("error_message", "Failed to load game."))
		return

	_refresh_continue_button()
	feedback_label.text = "Game loaded!"
	UIManager.push("game_ui")


# === Delete ===

func _on_delete_requested(save_id: String, username: String) -> void:
	_pending_delete_save_id = save_id
	_pending_delete_username = username
	delete_confirm_dialog.dialog_text = "Delete save \"%s\"?\nThis cannot be undone." % username
	delete_confirm_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	if _pending_delete_save_id == "":
		return
	var result: Dictionary = AccountService.delete_local_save(_pending_delete_save_id)
	var label: String = _pending_delete_username if _pending_delete_username != "" else _pending_delete_save_id
	_pending_delete_save_id = ""
	_pending_delete_username = ""

	if not bool(result.get("success", false)):
		feedback_label.text = str(result.get("error_message", "Failed to delete save."))
	else:
		feedback_label.text = "Deleted \"%s\"." % label

	_refresh_continue_button()
	if load_game_dialog.visible:
		load_game_dialog.refresh()


# === Diagnostics ===

func _kick_off_priming() -> void:
	# Start static-data priming the moment assets are reachable. On the warm
	# path this is a cheap signature check that completes before the user can
	# tap "New Game". On the cold path, the patch_progress signal feeds the
	# feedback label so the UI doesn't appear frozen.
	if StaticData.is_ready or StaticData._loading:
		return
	StaticData.prime_cache.call_deferred()


func _on_static_data_progress(file_name: String, _status: String) -> void:
	if StaticData.is_ready:
		return
	feedback_label.text = "Preparing data: %s…" % file_name


func _log_mem(tag: String) -> void:
	if not OS.is_debug_build():
		return
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
