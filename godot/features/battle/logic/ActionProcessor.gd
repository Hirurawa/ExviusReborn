extends Node
class_name ActionProcessor

# --- MAIN ROUTER ---
func execute_parsed_effect(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var func_name = "_apply_" + parsed_effect.get("type", "").to_lower()

	if has_method(func_name):
		return call(func_name, parsed_effect, caster, targets)
	else:
		push_warning("ActionProcessor: Unhandled effect type '%s'. No method '%s' found." % [parsed_effect.get("type", "UNKNOWN"), func_name])
		return []
		
# --- UTILITY FUNCTIONS ---
func _get_stat_safe(stats: Dictionary, stat_name: String, default_value: int = 10) -> int:
	if not stats.has(stat_name):
		push_error("CRITICAL BATTLE ERROR: Missing " + stat_name + " stat! Defaulting to " + str(default_value))
		return default_value
	return stats[stat_name]

# --- ---
func _apply_physical_damage(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [])
	var all_attack_frames = parsed_effect.get("attack_frames", [])
	var modifier = parsed_effect.get("effect", {}).get("modifier", 100.0) / 100.0

	var caster_stats = caster.get("final_stats", caster).get("stats", {})

	var all_hit_payloads: Array[Dictionary] = []

	for target in targets:
		var target_stats = target.get("final_stats", target)
		var ATK = _get_stat_safe(caster_stats, "ATK", 10)
		var DEF = _get_stat_safe(target_stats, "DEF", 10)

		var raw_damage = (float(ATK * ATK) / float(max(1, DEF))) * modifier
		var hit_payloads = EffectProcessor.generate_effect_payloads("DAMAGE", raw_damage, all_attack_damage, all_attack_frames, caster, target)
		
		for hit in hit_payloads:
			all_hit_payloads.append(hit)

	return all_hit_payloads

func _apply_magic_damage(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [])
	var all_attack_frames = parsed_effect.get("attack_frames", [])
	var modifier = parsed_effect.get("effect", {}).get("modifier", 100.0) / 100.0

	var caster_stats = caster.get("final_stats", caster).get("stats", {})

	var all_hit_payloads: Array[Dictionary] = []

	for target in targets:
		var target_stats = target.get("final_stats", target)
		var MAG = _get_stat_safe(caster_stats, "MAG", 10)
		var SPR = _get_stat_safe(target_stats, "SPR", 10)
			
		var raw_damage = (float(MAG * MAG) / float(max(1, SPR))) * modifier
		var hit_payloads = EffectProcessor.generate_effect_payloads("DAMAGE", raw_damage, all_attack_damage, all_attack_frames, caster, target)

		for hit in hit_payloads:
			all_hit_payloads.append(hit)

	return all_hit_payloads

func _apply_heal(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [])
	var all_attack_frames = parsed_effect.get("attack_frames", [])
	var effect = parsed_effect.get("effect", {})
	var modifier = effect.get("modifier", 100.0) / 100.0

	var caster_stats = caster.get("final_stats", caster).get("stats", {})

	var all_hit_payloads: Array[Dictionary] = []
	
	var SPR = _get_stat_safe(caster_stats, "SPR", 10)
	var MAG = _get_stat_safe(caster_stats, "MAG", 10)
	
	var raw_heal = effect.get("amount", 0) + (float(0.5 * SPR + 0.1 * MAG)) * modifier
	
	for target in targets:
		var hit_payloads = EffectProcessor.generate_effect_payloads(parsed_effect.get("type"), raw_heal, all_attack_damage, all_attack_frames, caster, target)
		for hit in hit_payloads:
			all_hit_payloads.append(hit)

	return all_hit_payloads

func _apply_stat_boost_pct(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	print("STAT BOOST %")
	return []
