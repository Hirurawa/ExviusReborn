extends Control

@onready var unit: TextureRect = $Pedestal/Unit
@onready var pedestal: TextureRect = $Pedestal
@onready var unit_name: Label = $UnitName

var unit_data_to_load = null
var scene_size = "small"

func _ready() -> void:
	if unit_data_to_load:
		setup(unit_data_to_load, scene_size)
	#var unit_data: Dictionary
	#unit_data = {"unitId": "100002204", "spriteOffset": "-11:21:150", "rare": "3"} # anzelm
	#unit_data = {"unitId": "100006805", "spriteOffset": "-5:15:150", "rare": "6"} # fohlen
	#unit_data = {"unitId": "201000203", "spriteOffset": "5:12:150", "rare": "6"} # garland
	#unit_data = {"unitId": "302000706", "spriteOffset": "-6:84:150", "rare": "6"} # w k noel
	#unit_data = {"unitId": "401006006", "spriteOffset": "0:52:150", "rare": "6"} # lucius
	#unit_data = {"unitId": "206000113", "spriteOffset": "-3:21:125", "rare": "3"} # magitek armor terra
	#unit_data = {"unitId": "206000504", "spriteOffset": "-4:18:150", "rare": "4"} # shadow
	#unit_data = {"unitId": "212000204", "spriteOffset": "-15:18:150", "rare": "4"} # ashe
	#setup(unit_data, "large")

func setup(unit_data: Dictionary, unit_size: String = "small") -> void:
	var offset_data = unit_data.get("spriteOffset").split(':')
	var x_offset: float = float(offset_data[0])
	var y_offset: float = float(offset_data[1])
	var sprite_scale: float = int(offset_data[2]) / 100.0
	
	var pedestal_texture_path = "res://assets/ui/unit/unit_charastand_rare%s_%s.tres" % [unit_data.get("rare"), unit_size]
	var pedestal_texture = ResourceLoader.load(pedestal_texture_path) as Texture2D
	pedestal.texture = pedestal_texture
	
	var unit_texture_path = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_data.get("unitId")
	var unit_texture = ResourceLoader.load(unit_texture_path) as Texture2D
	unit.texture = unit_texture
	unit.size = unit.texture.get_size()
	if unit_size == "small":
		unit.scale.x = sprite_scale
		unit.scale.y = sprite_scale
	else:
		unit.scale.x = 2.0
		unit.scale.y = 2.0
	
	# 1. Calculate the exact center of the Pedestal (The Target Destination)
	# For a 160x168 pedestal, this will be (80, 84)
	var pedestal_center = pedestal.size / 2.0

	# 2. Calculate the Unit's anchor point (The point we want to put on the destination)
	var unit_bottom_center = Vector2(unit.size.x / 2.0, unit.size.y)
	var final_offset = Vector2(-x_offset, -y_offset-40)
	var local_anchor_point = unit_bottom_center + final_offset

	# 3. Move the Unit
	# We subtract the anchor point from the center so that the anchor point 
	# lands exactly on the pedestal's center coordinate.
	unit.position = pedestal_center - local_anchor_point
