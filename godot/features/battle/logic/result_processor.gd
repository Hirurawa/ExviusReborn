extends Node
class_name ResultProcessor

const INSTANT_TYPES: Array[String] = ["damage", "heal", "mp_restore", "dispel"]

func apply_receipt(receipt: Dictionary, target: Dictionary) -> void:
	var type_str = receipt.get("type", "")
	if type_str == "":
		push_warning("ResultProcessor: Receipt has no type.")
		return

	if type_str.to_lower() in INSTANT_TYPES:
		var func_name = "_resolve_" + type_str.to_lower()
		if has_method(func_name):
			call(func_name, receipt, target)
		else:
			push_warning("ResultProcessor: Missing handler for receipt type: " + type_str)
	else:
		_resolve_status(receipt, target)

func _resolve_damage(receipt: Dictionary, target: Dictionary) -> void:
	var amount = receipt.get("amount", 0)
	var current_hp = target.get("current_hp", 0)
	target["current_hp"] = maxi(0, current_hp - amount)

func _resolve_heal(receipt: Dictionary, target: Dictionary) -> void:
	var amount = receipt.get("amount", 0)
	var current_hp = target.get("current_hp", 0)
	var max_hp = target.get("max_hp", 0)
	target["current_hp"] = mini(max_hp, current_hp + amount)

func _resolve_mp_restore(receipt: Dictionary, target: Dictionary) -> void:
	var amount = receipt.get("amount", 0)
	var current_mp = target.get("current_mp", 0)
	var max_mp = target.get("max_mp", 0)
	target["current_mp"] = mini(max_mp, current_mp + amount)

func _resolve_dispel(receipt: Dictionary, target: Dictionary) -> void:
	var target_types: Array = receipt.get("params", {}).get("target_types", [])
	if target_types.is_empty():
		push_warning("ResultProcessor: _resolve_dispel called with no target_types in params.")
		return

	var lower_types: Array[String] = []
	for t in target_types:
		lower_types.append(str(t).to_lower())

	target["active_effects"] = target.get("active_effects", []).filter(
		func(effect: Dictionary) -> bool: return not str(effect.get("type", "")).to_lower() in lower_types
	)
	target["final_stats"] = StatCalculator.calculate_final_stats(target)

func _resolve_status(receipt: Dictionary, target: Dictionary) -> void:
	if not target.has("active_effects"):
		target["active_effects"] = []

	var effect: Dictionary = {
		"type": receipt.get("type", ""),
		"duration": receipt.get("duration", 1),
		"params": receipt.get("params", {})
	}
	target["active_effects"].append(effect)
	target["final_stats"] = StatCalculator.calculate_final_stats(target)
