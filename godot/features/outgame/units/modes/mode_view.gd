extends GridMode
class_name ModeView


func handle_selection(unit_data, _context_node: Node) -> void:
	UIManager.push("unit_detail_ui", {"unit_inst": unit_data})
