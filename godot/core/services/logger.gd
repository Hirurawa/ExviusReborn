extends Node
## Logger — autoload that writes a session header and provides typed log helpers.
##
## All output is funneled through the standard Godot print / push_warning /
## push_error pipeline so the engine's built-in file logger (configured via
## ProjectSettings under `debug/file_logging/*`) captures it into a per-session
## file under `user://logs/`.
##
## Place this autoload FIRST so the session header is emitted before any other
## service starts logging.

const LOG_DIR: String = "user://logs/"


func _ready() -> void:
	# Make sure the log directory exists so the engine logger and any future
	# manual writes have somewhere to go.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	_write_session_header()


# === Public API ===

func info(msg: String, tag: String = "") -> void:
	print(_format("INFO", tag, msg))


func warn(msg: String, tag: String = "") -> void:
	push_warning(_format("WARN", tag, msg))


func error(msg: String, tag: String = "") -> void:
	push_error(_format("ERROR", tag, msg))


func dump_state(label: String, state: Dictionary) -> void:
	print(_format("STATE", label, JSON.stringify(state)))


func get_log_dir() -> String:
	return ProjectSettings.globalize_path(LOG_DIR)


# === Internals ===

func _format(level: String, tag: String, msg: String) -> String:
	var t: Dictionary = Time.get_time_dict_from_system()
	var ms: int = Time.get_ticks_msec() % 1000
	var stamp: String = "%02d:%02d:%02d.%03d" % [t.hour, t.minute, t.second, ms]
	if tag.is_empty():
		return "[%s][%s] %s" % [level, stamp, msg]
	return "[%s][%s][%s] %s" % [level, tag, stamp, msg]


func _write_session_header() -> void:
	var app_version: String = str(ProjectSettings.get_setting("application/config/version", "dev"))
	var engine_info: Dictionary = Engine.get_version_info()
	var device_id: String = OS.get_unique_id()
	if device_id.length() > 8:
		device_id = device_id.substr(0, 8)
	var lines: Array[String] = [
		"================ SESSION START ================",
		"  time:        %s" % Time.get_datetime_string_from_system(true),
		"  app:         %s" % app_version,
		"  engine:      %s" % engine_info.get("string", "?"),
		"  os:          %s" % OS.get_name(),
		"  distro:      %s" % OS.get_distribution_name(),
		"  model:       %s" % OS.get_model_name(),
		"  device_id:   %s" % device_id,
		"  log_dir:     %s" % get_log_dir(),
		"===============================================",
	]
	for line in lines:
		print(line)
