class_name TextureBuilder
extends RefCounted

static func load_unit_animation_data(unit_id: String) -> Dictionary:
	var png_path: String = "res://assets/unit_spritesheets/%s-atk.rawpng" % unit_id
	var json_path: String = "res://assets/unit_spritesheets/%s-atk.json" % unit_id

	if not FileAccess.file_exists(png_path) or not FileAccess.file_exists(json_path):
		return {}

	var file: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		return {}

	var json_text: String = file.get_as_text()
	var json_data: Variant = JSON.parse_string(json_text)
	if typeof(json_data) != TYPE_DICTIONARY:
		return {}

	var frame_rect: Dictionary = json_data.get("frameRect", {})
	var image_width: int = json_data.get("imageWidth", 0)
	var frame_width: int = frame_rect.get("width", 0)
	var frame_height: int = frame_rect.get("height", 0)

	if frame_width <= 0 or image_width <= 0:
		return {}

	var file_bytes: PackedByteArray = FileAccess.get_file_as_bytes(png_path)
	var image: Image = Image.new()
	var err: Error = image.load_png_from_buffer(file_bytes)
	if err != OK:
		return {}

	var num_frames: int = image_width / frame_width
	var frames: Array[Texture2D] = []

	for i in range(num_frames):
		var x: int = i * frame_width
		var region: Image = image.get_region(Rect2i(x, 0, frame_width, frame_height))
		frames.append(ImageTexture.create_from_image(region))

	var frame_delays: Array = json_data.get("frameDelays", [])

	return {
		"frames": frames,
		"delays": frame_delays,
		"frame_width": frame_width,
		"frame_height": frame_height,
		"num_frames": num_frames
	}
