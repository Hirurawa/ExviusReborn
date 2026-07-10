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


static func generate_effect_payloads(effect_type: String, raw_amount: int, attack_damage: Array, attack_frames: Array, caster: Dictionary, target: Dictionary, duration: int = 0, params: Dictionary = {}) -> Array:
	var generated_payloads = []

	var dmg_array = attack_damage[0] if typeof(attack_damage[0]) == TYPE_ARRAY else attack_damage
	var frame_array = attack_frames[0] if typeof(attack_frames[0]) == TYPE_ARRAY else attack_frames

	for i in range(dmg_array.size()):
		var percent = float(dmg_array[i]) / 100.0
		var split_amount = int(max(1, raw_amount * percent)) if raw_amount > 0 else 0

		var payload = {
			"type": effect_type,
			"frame_to_execute": frame_array[i],
			"amount": split_amount,
			"attacker_team": caster.get("team", ""),
			"attacker_index": caster.get("index", 0),
			"target_team": target.get("team", ""),
			"target_index": target.get("index", 0),
			"duration": duration,
			"params": params
		}

		generated_payloads.append(payload)

		# Status effects produce one payload per target — no multi-hit splitting needed.
		if duration > 0:
			break

	return generated_payloads

# --- ---
func _apply_physical_damage(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [[100]])
	var all_attack_frames = parsed_effect.get("attack_frames", [[0]])
	var modifier = parsed_effect.get("effect", {}).get("modifier", 100.0) / 100.0

	var caster_stats = caster.get("final_stats", caster).get("stats", {})

	var all_hit_payloads: Array[Dictionary] = []

	for target in targets:
		var target_stats = target.get("final_stats", target)
		target_stats = target_stats.get("stats", target_stats)
		var ATK = _get_stat_safe(caster_stats, "ATK", 10)
		var DEF = _get_stat_safe(target_stats, "DEF", 10)

		var raw_damage = (float(ATK * ATK) / float(max(1, DEF))) * modifier
		var hit_payloads = generate_effect_payloads("DAMAGE", raw_damage, all_attack_damage, all_attack_frames, caster, target)
		
		all_hit_payloads.append_array(hit_payloads)

	return all_hit_payloads

func _apply_magic_damage(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [[100]])
	var all_attack_frames = parsed_effect.get("attack_frames", [[0]])
	var modifier = parsed_effect.get("effect", {}).get("modifier", 100.0) / 100.0

	var caster_stats = caster.get("final_stats", caster).get("stats", {})

	var all_hit_payloads: Array[Dictionary] = []

	for target in targets:
		var target_stats = target.get("final_stats", target)
		target_stats = target_stats.get("stats", target_stats)
		var MAG = _get_stat_safe(caster_stats, "MAG", 10)
		var SPR = _get_stat_safe(target_stats, "SPR", 10)
			
		var raw_damage = (float(MAG * MAG) / float(max(1, SPR))) * modifier
		var hit_payloads = generate_effect_payloads("DAMAGE", raw_damage, all_attack_damage, all_attack_frames, caster, target)

		all_hit_payloads.append_array(hit_payloads)

	return all_hit_payloads

func _apply_spr_damage(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [[100]])
	var all_attack_frames = parsed_effect.get("attack_frames", [[0]])
	var modifier = parsed_effect.get("effect", {}).get("modifier", 100.0) / 100.0

	var caster_stats = caster.get("final_stats", caster).get("stats", {})

	var all_hit_payloads: Array[Dictionary] = []

	for target in targets:
		var target_stats = target.get("final_stats", target)
		target_stats = target_stats.get("stats", target_stats)
		var caster_SPR = _get_stat_safe(caster_stats, "SPR", 10)
		var target_SPR = _get_stat_safe(target_stats, "SPR", 10)
			
		var raw_damage = (float(caster_SPR * caster_SPR) / float(max(1, target_SPR))) * modifier
		var hit_payloads = generate_effect_payloads("DAMAGE", raw_damage, all_attack_damage, all_attack_frames, caster, target)

		all_hit_payloads.append_array(hit_payloads)

	return all_hit_payloads

func _apply_heal(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [[100]])
	var all_attack_frames = parsed_effect.get("attack_frames", [[0]])
	var effect = parsed_effect.get("effect", {})
	var modifier = effect.get("modifier", 100.0) / 100.0

	var caster_stats = caster.get("final_stats", caster).get("stats", {})

	var all_hit_payloads: Array[Dictionary] = []
	
	var SPR = _get_stat_safe(caster_stats, "SPR", 10)
	var MAG = _get_stat_safe(caster_stats, "MAG", 10)
	
	var raw_heal = effect.get("amount", 0) + (float(0.5 * SPR + 0.1 * MAG)) * modifier
	
	for target in targets:
		var hit_payloads = generate_effect_payloads(parsed_effect.get("type"), raw_heal, all_attack_damage, all_attack_frames, caster, target)
		all_hit_payloads.append_array(hit_payloads)

	return all_hit_payloads

func _apply_revive(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [[100]])
	var all_attack_frames = parsed_effect.get("attack_frames", [[0]])
	var effect = parsed_effect.get("effect", {})

	var all_hit_payloads: Array[Dictionary] = []
	
	var max_hp: int = int(targets[0].get("max_hp"))

	var revive_amount = float(effect.get("HP_pct", 0) )
	var heal_amount = int(round(max_hp * float((revive_amount / 100))))
	for target in targets:
		var hit_payloads = generate_effect_payloads("HEAL", heal_amount, all_attack_damage, all_attack_frames, caster, target)
		all_hit_payloads.append_array(hit_payloads)

	return all_hit_payloads

func _apply_hp_restore(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [[100]])
	var all_attack_frames = parsed_effect.get("attack_frames", [[0]])
	var effect = parsed_effect.get("effect", {})
	var amount = effect.get("amount", 100)
	
	var all_hit_payloads: Array[Dictionary] = []
	for target in targets:
		var hit_payloads = generate_effect_payloads("HEAL", amount, all_attack_damage, all_attack_frames, caster, target)
		all_hit_payloads.append_array(hit_payloads)
	return all_hit_payloads

func _apply_mp_restore(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [[100]])
	var all_attack_frames = parsed_effect.get("attack_frames", [[0]])
	var effect = parsed_effect.get("effect", {})
	var amount = effect.get("amount", 100)
	
	var all_hit_payloads: Array[Dictionary] = []
	for target in targets:
		var hit_payloads = generate_effect_payloads("MP_RESTORE", amount, all_attack_damage, all_attack_frames, caster, target)
		all_hit_payloads.append_array(hit_payloads)
	return all_hit_payloads

func _apply_stat_boost_pct(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [[100]])
	var all_attack_frames = parsed_effect.get("attack_frames", [[0]])
	var effect = parsed_effect.get("effect", {})

	var duration: int = effect.get("turn_count", 1)
	var params: Dictionary = effect.duplicate()
	params.erase("turn_count")

	var all_hit_payloads: Array[Dictionary] = []

	for target in targets:
		var hit_payloads = generate_effect_payloads("BUFF", 0, all_attack_damage, all_attack_frames, caster, target, duration, params)
		all_hit_payloads.append_array(hit_payloads)

	return all_hit_payloads

func _apply_dodge(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [[100]])
	var all_attack_frames = parsed_effect.get("attack_frames", [[0]])
	if all_attack_damage == []: all_attack_damage = [[100]]
	if all_attack_frames == []: all_attack_frames = [[0]]

	var effect = parsed_effect.get("effect", {})
	var duration: int = effect.get("turn_count", 1)
	var params: Dictionary = {"hits_to_dodge": effect.get("amount", 1)}

	var all_hit_payloads: Array[Dictionary] = []

	for target in targets:
		var hit_payloads = generate_effect_payloads(parsed_effect.get("type"), 0, all_attack_damage, all_attack_frames, caster, target, duration, params)
		all_hit_payloads.append_array(hit_payloads)

	return all_hit_payloads

func _apply_aoe_cover(parsed_effect: Dictionary, caster: Dictionary, targets: Array) -> Array[Dictionary]:
	var all_attack_damage = parsed_effect.get("attack_damage", [[100]])
	var all_attack_frames = parsed_effect.get("attack_frames", [[0]])
	if all_attack_damage == []: all_attack_damage = [[100]]
	if all_attack_frames == []: all_attack_frames = [[0]]

	var effect = parsed_effect.get("effect", {})
	var duration: int = effect.get("turn_count", 1)
	var params: Dictionary = {
		"dmg_reduce_min": effect.get("dmg_reduce_min", 0),
		"dmg_reduce_max": effect.get("dmg_reduce_max", 0),
		"pct_chance": effect.get("pct_chance", 100.0),
		"phys_mag": effect.get("phys_mag", "both")
	}

	var all_hit_payloads: Array[Dictionary] = []

	for target in targets:
		var hit_payloads = generate_effect_payloads(parsed_effect.get("type"), 0, all_attack_damage, all_attack_frames, caster, target, duration, params)
		all_hit_payloads.append_array(hit_payloads)

	return all_hit_payloads
