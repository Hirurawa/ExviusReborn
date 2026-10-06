# mode_select_base.gd
extends GridMode
class_name ModeSelectBase

var destination_screen: String
var custom_filter: Callable

# We pass the next screen's name, and an optional filtering function
func _init(p_destination: String, p_filter: Callable = Callable()) -> void:
	destination_screen = p_destination
	custom_filter = p_filter

func filter_units(units: Array) -> Array:
	# If a custom filter was provided, run it against the array
	if custom_filter.is_valid():
		return units.filter(custom_filter)
		
	# Otherwise, just return all units
	return units

func handle_selection(unit_data, _controller: Node) -> void:
	# Pop open the specific screen and pass the selected unit to it
	UIManager.push(destination_screen, {"base_unit": unit_data})
