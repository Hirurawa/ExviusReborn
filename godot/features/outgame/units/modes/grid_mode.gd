extends RefCounted
class_name GridMode

var selected_units: Array = []

# The currently selected sort option (defaults to the first one you want)
var active_sort_name: String = "Rarity"
var is_descending: bool = true

# A dictionary mapping the dropdown text to a Godot 4 lambda sorting rule.
# (Assuming your unit_data is a Dictionary, we use ['key']. If it becomes an Object later, use .key)
var sort_options: Dictionary = {
	"Rarity": func(a, b): return a["rare"] > b["rare"],
	"Level": func(a, b): return a["level"] > b["level"],
	"HP": func(a, b): return a["hp"] > b["hp"]
}


func uses_bottom_bar() -> bool:
	return false 

func filter_units(units: Array) -> Array:
	return units

func sort_units(units: Array) -> Array:
	var sorted = units.duplicate()
	
	var sort_rule = sort_options.get(active_sort_name)
	if sort_rule.is_valid():
		sorted.sort_custom(sort_rule)
	
	if not is_descending:
		sorted.reverse()
		
	return sorted


func wants_remove_button() -> bool:
	return false


func handle_selection(_unit_data, _controller: Node) -> void:
	pass
	
func clear_selection(controller: Node) -> void:
	selected_units.clear()
	controller.refresh_selection_visuals()
