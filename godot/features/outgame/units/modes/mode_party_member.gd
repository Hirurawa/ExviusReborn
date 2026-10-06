extends GridMode
class_name ModeSelectPartyMember

var unit_instance: Dictionary
var party_idx: int
var slot_idx: int
var custom_filter: Callable

func _init(unit: Dictionary, party_num: int, slot_num: int, p_filter: Callable = Callable()) -> void:
	unit_instance = unit
	party_idx = party_num
	slot_idx = slot_num
	custom_filter = p_filter


func wants_remove_button() -> bool:
	return unit_instance != {}


func filter_units(units: Array) -> Array:
	if custom_filter.is_valid():
		return units.filter(custom_filter)
	return units#.filter(func(u): return u.instance_id != unit_instance.instance_id)

func handle_selection(unit_data, _controller: Node) -> void:
	#unit_selected.emit(unit_data)
	PartyService.assign_unit_to_party(party_idx, slot_idx, unit_data.get("instance_id", ""))
	UIManager.pop()
