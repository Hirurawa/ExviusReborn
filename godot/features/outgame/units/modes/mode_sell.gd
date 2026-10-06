# mode_sell.gd
extends ModeMultiSelect
class_name ModeSell

func _init() -> void:
	# Add a custom sorting option just for selling
	sort_options["Sell Value"] = func(a, b): return a["amountSell"] > b["amountSell"]
	
	# Optionally force the dropdown to default to this when selling
	active_sort_name = "Sell Value"

# Optional: Add specific filters for selling
func filter_units(units: Array) -> Array:
	return units.filter(func(u): return u)#.is_sellable and not u.is_locked)

func on_ok_pressed(controller: Node) -> void:
	if selected_units.is_empty():
		return
	controller.show_sell_confirmation(selected_units)
	selected_units.clear()
