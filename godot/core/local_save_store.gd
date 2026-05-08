extends RefCounted

const SAVE_DIR: String = "user://game_state"
const SNAPSHOT_SCHEMA_VERSION: int = 1

func save_snapshot(file_name: String, payload: Dictionary, source_event: String) -> bool:
	if file_name.strip_edges() == "":
		push_error("LocalSaveStore: file_name cannot be empty")
		return false

	if not _ensure_save_dir():
		return false

	var envelope: Dictionary = {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"saved_at_unix_ms": Time.get_unix_time_from_system() * 1000,
		"source_event": source_event,
		"data": payload
	}

	var json_text: String = JSON.stringify(envelope, "\t")
	var final_path: String = "%s/%s" % [SAVE_DIR, file_name]
	var temp_path: String = "%s.tmp" % final_path

	if not _write_text_file(temp_path, json_text):
		return false

	if DirAccess.rename_absolute(temp_path, final_path) == OK:
		return true

	# Fallback path if atomic rename is unavailable on the target platform.
	if not _write_text_file(final_path, json_text):
		return false

	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)

	return true

func load_snapshot(file_name: String) -> Dictionary:
	if file_name.strip_edges() == "":
		return {}

	var path: String = "%s/%s" % [SAVE_DIR, file_name]
	if not FileAccess.file_exists(path):
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("LocalSaveStore: failed to open file for read: %s" % path)
		return {}

	var content: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(content)
	if not (parsed is Dictionary):
		push_warning("LocalSaveStore: invalid JSON snapshot: %s" % path)
		return {}

	return parsed

func _ensure_save_dir() -> bool:
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		return true

	var err: Error = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK:
		push_error("LocalSaveStore: failed to create save directory %s" % SAVE_DIR)
		return false

	return true

func _write_text_file(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("LocalSaveStore: failed to open file for write: %s" % path)
		return false

	file.store_string(text)
	file.close()
	return true
