@tool
extends Control

const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg"]

@export_file("*.csv") var layout_csv: String
@export_dir var plist_directory: String = ""
@export_dir var atlas_texture_directory: String = ""
@export_dir var tres_directory: String = "res://assets/ui/"
@export var build_textured_ui: bool = false:
	set(value):
		if value:
			_build_ui()
			build_textured_ui = false

func _build_ui() -> void:
	if layout_csv == "" or plist_directory == "" or tres_directory == "":
		print("Please assign the CSV, plist directory, and .tres output directory.")
		return

	if not tres_directory.begins_with("res://"):
		print("The .tres output directory must be inside the project (res://...).")
		return

	var entries: Array[Dictionary] = _parse_layout_entries()
	if entries.is_empty():
		print("No valid layout rows found in CSV.")
		return

	var required_textures: Array[String] = _collect_required_textures(entries)
	var sprite_index: Dictionary = _index_sprites(required_textures)
	var missing_textures: Array[String] = _find_missing_textures(required_textures, sprite_index)

	if not missing_textures.is_empty():
		print("Missing sprites in plist files: ", ", ".join(missing_textures))

	if not _ensure_output_directory_exists():
		print("Failed to create output directory: ", tres_directory)
		return

	_generate_texture_resources(required_textures, sprite_index)
	_clear_existing_children()
	_assemble_ui(entries)
	print("UI Assembly Complete!")

func _parse_layout_entries() -> Array[Dictionary]:
	var file: FileAccess = FileAccess.open(layout_csv, FileAccess.READ)
	if not file:
		print("Failed to open CSV: ", layout_csv)
		return []

	var entries: Array[Dictionary] = []
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() < 6:
			continue

		var x: int = line[0].to_int()
		var y: int = line[1].to_int()
		var w: int = line[2].to_int()
		var h: int = line[3].to_int()
		var param: int = line[4].to_int()
		var id: String = line[5].strip_edges()
		var tex_name: String = line[6].strip_edges() if line.size() > 6 else ""

		if x < 0:
			x = 0
		if w <= 0 or h <= 0:
			continue

		entries.append({
			"x": x,
			"y": y,
			"w": w,
			"h": h,
			"param": param,
			"id": id,
			"texture": _normalize_texture_name(tex_name)
		})

	return entries

func _collect_required_textures(entries: Array[Dictionary]) -> Array[String]:
	var unique_textures: Dictionary = {}

	for entry in entries:
		var texture_name: String = entry.get("texture", "")
		if texture_name != "":
			unique_textures[texture_name] = true

	var textures: Array[String] = []
	for texture_name in unique_textures.keys():
		textures.append(texture_name)

	textures.sort()
	return textures

func _index_sprites(required_textures: Array[String]) -> Dictionary:
	var requested_textures: Dictionary = {}
	for texture_name in required_textures:
		requested_textures[texture_name] = true

	var plist_paths: Array[String] = []
	_collect_files_with_extension(plist_directory, "plist", plist_paths)

	if plist_paths.is_empty():
		print("No plist files found in: ", plist_directory)
		return {}

	var sprite_index: Dictionary = {}
	for plist_path in plist_paths:
		_index_plist_file(plist_path, requested_textures, sprite_index)

	return sprite_index

func _index_plist_file(plist_path: String, requested_textures: Dictionary, sprite_index: Dictionary) -> void:
	var atlas_path: String = _resolve_atlas_texture_path(plist_path)
	if atlas_path == "":
		print("Skipping plist with no matching atlas image: ", plist_path)
		return

	var file: FileAccess = FileAccess.open(plist_path, FileAccess.READ)
	if not file:
		print("Failed to open plist file: ", plist_path)
		return

	var current_sprite_name: String = ""
	var is_next_line_rect: bool = false

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()

		if line == "<key>textureRect</key>":
			is_next_line_rect = current_sprite_name != ""
			continue

		if line.begins_with("<key>") and line.ends_with("</key>"):
			var key_name: String = line.replace("<key>", "").replace("</key>", "").strip_edges()
			current_sprite_name = key_name if requested_textures.has(key_name) else ""
			continue

		if not is_next_line_rect or not line.begins_with("<string>"):
			continue

		is_next_line_rect = false
		var region: Rect2 = _parse_texture_rect(line)
		if region.size.x <= 0.0 or region.size.y <= 0.0:
			current_sprite_name = ""
			continue

		if sprite_index.has(current_sprite_name):
			var existing_source: String = sprite_index[current_sprite_name].get("plist_path", "")
			print("Duplicate sprite entry found for ", current_sprite_name, ": ", existing_source, " and ", plist_path)
			current_sprite_name = ""
			continue

		sprite_index[current_sprite_name] = {
			"atlas_path": atlas_path,
			"region": region,
			"plist_path": plist_path
		}
		current_sprite_name = ""

func _resolve_atlas_texture_path(plist_path: String) -> String:
	var base_name: String = plist_path.get_file().get_basename()
	var search_directory: String = atlas_texture_directory if atlas_texture_directory != "" else plist_path.get_base_dir()

	for extension in IMAGE_EXTENSIONS:
		var candidate_path: String = _join_path(search_directory, "%s.%s" % [base_name, extension])
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

func _find_missing_textures(required_textures: Array[String], sprite_index: Dictionary) -> Array[String]:
	var missing_textures: Array[String] = []

	for texture_name in required_textures:
		if not sprite_index.has(texture_name):
			missing_textures.append(texture_name)

	return missing_textures

func _ensure_output_directory_exists() -> bool:
	return DirAccess.make_dir_recursive_absolute(tres_directory) == OK

func _generate_texture_resources(required_textures: Array[String], sprite_index: Dictionary) -> void:
	var atlas_cache: Dictionary = {}

	for texture_name in required_textures:
		if not sprite_index.has(texture_name):
			continue

		var sprite_data: Dictionary = sprite_index[texture_name]
		var atlas_path: String = sprite_data.get("atlas_path", "")
		var region: Rect2 = sprite_data.get("region", Rect2())

		if atlas_path == "":
			continue

		if not atlas_cache.has(atlas_path):
			atlas_cache[atlas_path] = _load_texture_from_path(atlas_path)

		var master_texture: Texture2D = atlas_cache.get(atlas_path)
		if master_texture == null:
			print("Failed to load atlas texture: ", atlas_path)
			continue

		_create_atlas_texture(master_texture, texture_name, region)

func _load_texture_from_path(texture_path: String) -> Texture2D:
	if texture_path.begins_with("res://") or texture_path.begins_with("uid://"):
		return load(texture_path)

	var image: Image = Image.new()
	var error: Error = image.load(texture_path)
	if error != OK:
		return null

	return ImageTexture.create_from_image(image)

func _clear_existing_children() -> void:
	for child in get_children():
		child.queue_free()

func _build_tres_index() -> Dictionary:
	var index: Dictionary = {}
	var paths: Array[String] = []
	_collect_files_with_extension(tres_directory, "tres", paths)
	for path in paths:
		var key: String = path.get_file().get_basename()
		if not index.has(key):
			index[key] = path
	return index

func _assemble_ui(entries: Array[Dictionary]) -> void:
	print("Assembling UI from: ", layout_csv)
	var tres_index: Dictionary = _build_tres_index()

	for entry in entries:
		var x: int = entry.get("x", 0)
		var y: int = entry.get("y", 0)
		var w: int = entry.get("w", 0)
		var h: int = entry.get("h", 0)
		var param: int = entry.get("param", 0)
		var id: String = entry.get("id", "")
		var tex_name: String = entry.get("texture", "")

		var ui_node: Control

		if tex_name != "":
			var tex_rect: TextureRect = TextureRect.new()
			var tex_key: String = tex_name.get_file().get_basename()
			var tres_path: String = tres_index.get(tex_key, "")

			if tres_path != "":
				tex_rect.texture = load(tres_path)
			else:
				print("Missing texture resource: ", tex_key, ".tres")

			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ui_node = tex_rect
		else:
			var label: Label = Label.new()
			label.text = id
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

			if param > 0:
				label.add_theme_font_size_override("font_size", param)

			if "touch" in id or "area" in id:
				var style: StyleBoxFlat = StyleBoxFlat.new()
				style.bg_color = Color(1.0, 0.0, 0.0, 0.2)
				label.add_theme_stylebox_override("normal", style)

			ui_node = label

		ui_node.name = id
		ui_node.position = Vector2(x, y)
		ui_node.size = Vector2(w, h)

		add_child(ui_node)
		ui_node.owner = get_tree().edited_scene_root

func _create_atlas_texture(master_tex: Texture2D, save_name: String, region: Rect2) -> void:
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = master_tex
	atlas.region = region

	var save_path: String = _get_tres_path(save_name)
	var save_result: Error = ResourceSaver.save(atlas, save_path)
	if save_result != OK:
		print("Failed to save atlas texture: ", save_path)

func _get_tres_path(texture_name: String) -> String:
	var file_name: String = texture_name.get_file().get_basename()
	return _join_path(tres_directory.trim_suffix("/"), "%s.tres" % file_name)

func _normalize_texture_name(texture_name: String) -> String:
	var normalized: String = texture_name.strip_edges()
	if normalized == "":
		return ""

	return normalized.get_file()

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
