class_name BattleBackground
extends TextureRect

## The battle's backdrop (BattleUI's Background): the mission's jpg and the SpriteStudio
## animations the game plays over it (waterfalls, glowing moss, fog, rain, light rays).
## battle_bg's layer column (GameDatabase.get_mission_bg_layers) names them, for example
##   battle_bg_0003_01.ssbp#battle_bg_0003_01,back/anime,0,216&battle_bg_0003_01,front/anime,1
## Layers are separated by "&"; the first names the .ssbp before "#"; then come the cell
## map, "pack/animation", the layer and an offset. Layer 0 plays here, over the jpg and
## under the units; higher layers play in `front`, over the units, in layer order.
##
## An animation's origin sits on the jpg's vertical centre line, `offset` pixels below
## the picture's centre (216 in nearly every entry; checked against 12 backgrounds). Most
## front layers give no offset and reuse the one before them: their extents match their
## back layers' at 216. Backgrounds whose .ssbp is not in the assets show the jpg alone.
## See CUTSCENE-PLAN.md section 9.3.

## The .ssbp files are looked for in every folder under res://assets/ whose name starts
## with this: the game's battleBg1 package and any later ones.
const SSBP_FOLDER_PREFIX: String = "battleBg"
const DEFAULT_OFFSET: int = 216

## Over the units, clipped to the battle field (BattleUI's BackgroundFront).
@export var front: Control

## The animations playing, back ones first.
var players: Array[SsbpPlayer] = []

static var _ssbp_paths: Dictionary = {}  # file name -> res:// path


## Shows `picture` with the animations of `layers` (battle_bg's layer column; "" for none).
func show_background(picture: Texture2D, layers: String) -> void:
	texture = picture
	for player in players:
		player.get_parent().remove_child(player)
		player.queue_free()
	players.clear()
	var entries: Array = parse_layers(layers)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["layer"] < b["layer"])
	for entry in entries:
		var path: String = ssbp_path(entry["file"])
		if path == "":
			continue
		var player := SsbpPlayer.new()
		player.name = "%s_%s" % [entry["file"].get_basename(), entry["animation"].replace("/", "_")]
		player.open(path, entry["animation"])
		var parent: CanvasItem = self if entry["layer"] == 0 or front == null else front
		parent.add_child(player)
		player.position = parent.get_global_transform().affine_inverse() * (get_global_transform() * origin(entry["offset"]))
		players.append(player)


## Where an animation with `offset` has its origin, in this node's space: the jpg is drawn
## centred at its own size (stretch mode Keep Centered).
func origin(offset: int) -> Vector2:
	return size / 2.0 + Vector2(0, offset)


## The layers of a battle_bg layer column: [{file, animation, layer, offset}].
static func parse_layers(text: String) -> Array:
	var layers: Array = []
	var file: String = ""
	var offset: int = DEFAULT_OFFSET
	for entry in text.split("&", false):
		var fields_text: String = entry
		if entry.contains("#"):
			file = entry.get_slice("#", 0)
			fields_text = entry.get_slice("#", 1)
		var fields: PackedStringArray = fields_text.split(",")
		if file == "" or fields.size() < 3:
			continue
		if fields.size() > 3:
			offset = int(fields[3])
		layers.append({"file": file, "animation": fields[1], "layer": int(fields[2]), "offset": offset})
	return layers


## The res:// path of .ssbp file `file_name`, or "" when no battleBg folder has it.
static func ssbp_path(file_name: String) -> String:
	if _ssbp_paths.is_empty():
		for folder in DirAccess.get_directories_at("res://assets/"):
			if not folder.begins_with(SSBP_FOLDER_PREFIX):
				continue
			for file in DirAccess.get_files_at("res://assets/" + folder):
				if file.ends_with(".ssbp"):
					_ssbp_paths[file] = "res://assets/%s/%s" % [folder, file]
	return _ssbp_paths.get(file_name, "")
