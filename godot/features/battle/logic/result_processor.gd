extends Node
class_name ResultProcessor

func apply_receipt(receipt: Dictionary, target: Dictionary) -> void:
	var type_str = receipt.get("type", "")
	if type_str == "":
		push_warning("ResultProcessor: Receipt has no type.")
		return

	var func_name = "_resolve_" + type_str.to_lower()

	if has_method(func_name):
		call(func_name, receipt, target)
	else:
		push_warning("ResultProcessor: Missing handler for receipt type: " + type_str)

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

func _resolve_buff(receipt: Dictionary, target: Dictionary) -> void:
	if not target.has("active_effects"):
		target["active_effects"] = []

	var effect = {
		"duration": receipt.get("duration", 3),
		"modifiers": receipt.get("modifiers", {})
	}
	target["active_effects"].append(effect)
	target["final_stats"] = StatCalculator.calculate_final_stats(target)
	
func _resolve_debuff(receipt: Dictionary, target: Dictionary) -> void:
	if not target.has("active_effects"):
		target["active_effects"] = []

	var effect = {
		"duration": receipt.get("duration", 3),
		"modifiers": receipt.get("modifiers", {})
	}
	target["active_effects"].append(effect)
	target["final_stats"] = StatCalculator.calculate_final_stats(target)

func _resolve_dodge(receipt: Dictionary, target: Dictionary) -> void:
	if not target.has("active_effects"):
		target["active_effects"] = []

	var effect = {
		"duration": receipt.get("duration", 3),
		"hits_to_dodge": receipt.get("hits_to_dodge", {})
	}
	target["active_effects"].append(effect)
	
func _resolve_aoe_cover(receipt: Dictionary, target: Dictionary) -> void:
	if not target.has("active_effects"):
		target["active_effects"] = []

	var effect = {
		"type": "AOE_COVER",
		"duration": receipt.get("duration", 3),
		"dmg_reduce_min": receipt.get("dmg_reduce_min"),
		"dmg_reduce_max": receipt.get("dmg_reduce_max"),
		"pct_chance": receipt.get("pct_chance"),
		"phys_mag": receipt.get("phys_mag")
	}
	target["active_effects"].append(effect)
	
