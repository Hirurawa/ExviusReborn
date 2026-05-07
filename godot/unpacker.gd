@tool
extends Control

const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg"]

@export_dir var source_directory: String = ""
@export var overwrite_existing: bool = false
@export var extract_from_folder: bool = false:
	set(value):
		if value:
			_extract_all()
			extract_from_folder = false

func _extract_all() -> void:
	if source_directory == "":
		print("Please assign source directory.")
		return

	var plist_paths: Array[String] = []
	_collect_files_with_extension(source_directory, "plist", plist_paths)
	plist_paths.sort()

	if plist_paths.is_empty():
		print("No plist files found in: ", source_directory)
		return

	var atlas_cache: Dictionary = {}
	var total_sprites: int = 0
	var created_count: int = 0
	var overwritten_count: int = 0
	var skipped_count: int = 0
	var failed_count: int = 0
	var atlas_missing_count: int = 0

	for plist_path in plist_paths:
		var atlas_path: String = _resolve_atlas_texture_path(plist_path)
		if atlas_path == "":
			atlas_missing_count += 1
			print("Skipping plist with no matching atlas image: ", plist_path)
			continue

		if not atlas_cache.has(atlas_path):
			atlas_cache[atlas_path] = _load_texture_from_path(atlas_path)

		var master_texture: Texture2D = atlas_cache.get(atlas_path, null)
		if master_texture == null:
			failed_count += 1
			print("Failed to load atlas image for plist: ", plist_path)
			continue

		var sprites: Array[Dictionary] = _parse_plist_sprites(plist_path)
		if sprites.is_empty():
			continue

		for sprite in sprites:
			total_sprites += 1
			var sprite_name: String = sprite.get("name", "")
			var region: Rect2 = sprite.get("region", Rect2())

			if sprite_name == "" or region.size.x <= 0.0 or region.size.y <= 0.0:
				failed_count += 1
				continue

			var save_path: String = _get_tres_path(sprite_name, atlas_path)
			var save_outcome: int = _save_sprite_tres(master_texture, region, save_path)
			match save_outcome:
				0:
					created_count += 1
				1:
					overwritten_count += 1
				2:
					skipped_count += 1
				_:
					failed_count += 1

	print(
		"Extraction complete. Plists: ", plist_paths.size(),
		", Sprites parsed: ", total_sprites,
		", Created: ", created_count,
		", Overwritten: ", overwritten_count,
		", Skipped: ", skipped_count,
		", Failed: ", failed_count,
		", Missing atlas: ", atlas_missing_count
	)

func _parse_plist_sprites(plist_path: String) -> Array[Dictionary]:
	var file: FileAccess = FileAccess.open(plist_path, FileAccess.READ)
	if not file:
		print("Failed to open plist file: ", plist_path)
		return []

	var sprites: Array[Dictionary] = []
	var current_sprite_name: String = ""
	var is_next_line_rect: bool = false

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()

		if line.begins_with("<key>") and line.ends_with("</key>"):
			var key_name: String = line.replace("<key>", "").replace("</key>", "").strip_edges()

			if _is_sprite_key(key_name):
				current_sprite_name = key_name
				is_next_line_rect = false
				continue

			if key_name == "textureRect" and current_sprite_name != "":
				is_next_line_rect = true
				continue

		if not is_next_line_rect or not line.begins_with("<string>"):
			continue

		is_next_line_rect = false
		var region: Rect2 = _parse_texture_rect(line)
		if region.size.x <= 0.0 or region.size.y <= 0.0:
			current_sprite_name = ""
			continue

		sprites.append({
			"name": current_sprite_name,
			"region": region
		})
		current_sprite_name = ""

	return sprites

func _is_sprite_key(key_name: String) -> bool:
	var key_lower: String = key_name.to_lower()
	for extension in IMAGE_EXTENSIONS:
		if key_lower.ends_with(".%s" % extension):
			return true
	return false

func _resolve_atlas_texture_path(plist_path: String) -> String:
	var base_name: String = plist_path.get_file().get_basename()
	var plist_directory: String = plist_path.get_base_dir()

	for extension in IMAGE_EXTENSIONS:
		var candidate_path: String = _join_path(plist_directory, "%s.%s" % [base_name, extension])
		if FileAccess.file_exists(candidate_path):
			return candidate_path

	return ""

func _parse_texture_rect(line: String) -> Rect2:
	var clean_rect: String = line.replace("<string>", "").replace("</string>", "")
	clean_rect = clean_rect.replace("{", "").replace("}", "")
	var parts: PackedStringArray = clean_rect.split(",")

	if parts.size() != 4:
		return Rect2()

	return Rect2(
		parts[0].to_int(),
		parts[1].to_int(),
		parts[2].to_int(),
		parts[3].to_int()
	)

func _save_sprite_tres(master_tex: Texture2D, region: Rect2, save_path: String) -> int:
	var exists: bool = FileAccess.file_exists(save_path)
	if exists and not overwrite_existing:
		return 2

	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = master_tex
	atlas.region = region

	var save_result: Error = ResourceSaver.save(atlas, save_path)
	if save_result != OK:
		print("Failed to save atlas texture: ", save_path)
		return 3

	if exists:
		return 1
	return 0

func _get_tres_path(texture_name: String, atlas_path: String) -> String:
	var file_name: String = texture_name.get_file().get_basename()
	var atlas_directory: String = atlas_path.get_base_dir().trim_suffix("/")
	return _join_path(atlas_directory, "%s.tres" % file_name)

func _load_texture_from_path(texture_path: String) -> Texture2D:
	if texture_path.begins_with("res://") or texture_path.begins_with("uid://"):
		return load(texture_path)

	var image: Image = Image.new()
	var error: Error = image.load(texture_path)
	if error != OK:
		return null

	return ImageTexture.create_from_image(image)

func _collect_files_with_extension(root_directory: String, extension: String, output: Array[String]) -> void:
	var directory: DirAccess = DirAccess.open(root_directory)
	if directory == null:
		print("Failed to open directory: ", root_directory)
		return

	directory.list_dir_begin()
	while true:
		var entry_name: String = directory.get_next()
		if entry_name == "":
			break
		if entry_name == "." or entry_name == "..":
			continue

		var entry_path: String = _join_path(root_directory, entry_name)
		if directory.current_is_dir():
			_collect_files_with_extension(entry_path, extension, output)
		elif entry_name.get_extension().to_lower() == extension:
			output.append(entry_path)

	directory.list_dir_end()

func _join_path(dir_path: String, file_name: String) -> String:
	if dir_path.ends_with("/"):
		return "%s%s" % [dir_path, file_name]
	return "%s/%s" % [dir_path, file_name]
