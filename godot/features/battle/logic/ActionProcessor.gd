extends Node
class_name ActionProcessor

func execute_parsed_effect(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var func_name = "_apply_" + parsed_effect.get("type", "").to_lower()

	if has_method(func_name):
		return call(func_name, parsed_effect, caster, targets)
	else:
		push_warning("ActionProcessor: Unhandled effect type '%s'. No method '%s' found." % [parsed_effect.get("type", "UNKNOWN"), func_name])
		return []

func _apply_magic_damage(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [])
	var all_attack_frames = parsed_effect.get("attack_frames", [])
	var modifier = parsed_effect.get("effect", {}).get("modifier", 100.0) / 100.0

	var caster_stats = caster.get("final_stats", caster).get("stats", {}) # Fallback to base dict if final_stats missing

	var all_hit_payloads: Array[Dictionary] = []

	for target in targets:
		var target_stats = target.get("final_stats", target)

		var raw_damage = EffectProcessor.calculate_raw_damage(parsed_effect.get("type"), modifier, caster_stats, target_stats)
		var hit_payloads = EffectProcessor.generate_hit_payloads(raw_damage, all_attack_damage, all_attack_frames, caster.get("team"), caster.get("index"), target.get("team"), target.get("index"))

		for hit in hit_payloads:
			all_hit_payloads.append(hit)

	return all_hit_payloads

func _apply_physical_damage(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [])
	var all_attack_frames = parsed_effect.get("attack_frames", [])
	var modifier = parsed_effect.get("effect", {}).get("modifier", 100.0) / 100.0

	var caster_stats = caster.get("final_stats", caster).get("stats", {}) # Fallback to base dict if final_stats missing

	var all_hit_payloads: Array[Dictionary] = []

	for target in targets:
		var target_stats = target.get("final_stats", target)

		var raw_damage = EffectProcessor.calculate_raw_damage(parsed_effect.get("type"), modifier, caster_stats, target_stats)
		var hit_payloads = EffectProcessor.generate_hit_payloads(raw_damage, all_attack_damage, all_attack_frames, caster.get("team"), caster.get("index"), target.get("team"), target.get("index"))

		for hit in hit_payloads:
			all_hit_payloads.append(hit)

	return all_hit_payloads

func _apply_heal(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	print("HEALING")
	return []

func _apply_stat_boost_pct(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	print("STAT BOOST %")
	return []
