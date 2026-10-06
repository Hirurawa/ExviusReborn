# mode_multi_select.gd
extends GridMode
class_name ModeMultiSelect

var max_selections: int = 0 # 0 means unlimited

func uses_bottom_bar() -> bool:
	return true

func handle_selection(unit_data, controller: Node) -> void:
	if unit_data in selected_units:
		selected_units.erase(unit_data)
	else:
		# Respect the selection limit if one is set
		if max_selections <= 0 or selected_units.size() < max_selections:
			selected_units.append(unit_data)
			
	controller.refresh_selection_visuals()

# We add a new virtual function for what happens when the OK button is pressed
func on_ok_pressed(_controller: Node) -> void:
	pass
