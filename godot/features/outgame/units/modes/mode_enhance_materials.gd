# mode_enhance_materials.gd
extends ModeMultiSelect
class_name ModeEnhanceMaterials

var base_unit: Dictionary
var on_complete_callback: Callable

func _init(p_base_unit: Dictionary, p_callback: Callable) -> void:
	base_unit = p_base_unit
	on_complete_callback = p_callback
	max_selections = 5


func filter_units(units: Array) -> Array:
	return units.filter(func(u): return u.instance_id != base_unit.instance_id)


func on_ok_pressed(controller: Node) -> void:
	if on_complete_callback.is_valid():
		on_complete_callback.call(selected_units)
	
	UIManager.pop()
