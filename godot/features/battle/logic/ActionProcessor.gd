extends Node
class_name ActionProcessor

func execute_parsed_effect(parsed_effect: Dictionary, caster: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var func_name = "_apply_" + parsed_effect.get("type", "").to_lower()

	if has_method(func_name):
		return call(func_name, parsed_effect, caster, targets)
	else:
		push_warning("ActionProcessor: Unhandled effect type '%s'. No method '%s' found." % [parsed_effect.get("type", "UNKNOWN"), func_name])
		return []

func _apply_magic_damage(parsed_effect: Dictionary, caster: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	return _process_standard_damage(parsed_effect, caster, targets)

func _apply_physical_damage(parsed_effect: Dictionary, caster: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	return _process_standard_damage(parsed_effect, caster, targets)

func _apply_basic_attack(parsed_effect: Dictionary, caster: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	return _process_standard_damage(parsed_effect, caster, targets)

func _process_standard_damage(effect: Dictionary, caster: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var all_attack_damage = effect.get("attack_damage", [])
	var all_attack_frames = effect.get("attack_frames", [])
	var modifier = effect.get("effect", {}).get("modifier", 100.0) / 100.0

	var caster_stats = caster.get("final_stats", caster).get("stats", {}) # Fallback to base dict if final_stats missing

	var all_hit_payloads: Array[Dictionary] = []

	for target in targets:
		var target_stats = target.get("final_stats", target)

		var raw_damage = EffectProcessor.calculate_raw_damage(effect.get("type"), modifier, caster_stats, target_stats)
		var hit_payloads = EffectProcessor.generate_hit_payloads(raw_damage, all_attack_damage, all_attack_frames, caster.get("team"), caster.get("index"), target.get("team"), target.get("index"))

		for hit in hit_payloads:
			all_hit_payloads.append(hit)

	return all_hit_payloads
