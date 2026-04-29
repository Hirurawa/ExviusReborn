extends Control

@onready var equip_name: Label = $unit_equip_list_name_text
@onready var unit_equip_cat: TextureRect = $UnitEquipCategory
@onready var equip_cat: TextureRect = $EquipCategory
@onready var prop_label_1: TextureRect = $unit_equip_list_property1_label
@onready var prop_number_1: Label = $unit_equip_list_property1_number
@onready var prop_label_2: TextureRect = $unit_equip_list_property2_label
@onready var prop_number_2: Label = $unit_equip_list_property2_number

func _ready() -> void:
	pass
