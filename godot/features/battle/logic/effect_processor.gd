class_name EffectProcessor

static func calculate_raw_damage(effect_type: String, modifier: float, caster_stats: Dictionary, target_stats: Dictionary) -> int:
	var offensive_stat: int = 1
	var defensive_stat: int = 1
	
	if effect_type == "PHYSICAL_DAMAGE" or effect_type == "BASIC_ATTACK":
		if not caster_stats.has("ATK"):
			push_error("CRITICAL BATTLE ERROR: Caster is missing ATK stat! Defaulting to 10.")
			offensive_stat = 10
		else:
			offensive_stat = caster_stats.get("ATK")
			
		if not target_stats.has("DEF"):
			push_error("CRITICAL BATTLE ERROR: Target is missing DEF stat! Defaulting to 10.")
			defensive_stat = 10
		else:
			defensive_stat = target_stats.get("DEF")
			
	elif effect_type == "MAGIC_DAMAGE":
		if not caster_stats.has("MAG"):
			push_error("CRITICAL BATTLE ERROR: Caster is missing MAG stat! Defaulting to 10.")
			offensive_stat = 10
		else:
			offensive_stat = caster_stats.get("MAG")
			
		if not target_stats.has("SPR"):
			push_error("CRITICAL BATTLE ERROR: Target is missing SPR stat! Defaulting to 10.")
			defensive_stat = 10
		else:
			defensive_stat = target_stats.get("SPR")
			
	# Classic quadratic formula: (Stat * Stat / Defense) * Modifier
	# We still use max(1, defensive_stat) to strictly prevent division-by-zero engine crashes
	var raw = (float(offensive_stat * offensive_stat) / float(max(1, defensive_stat))) * modifier
	return int(max(1, raw))

static func generate_hit_payloads(raw_damage: int, attack_damage: Array, attack_frames: Array, attacker_team: String, attacker_idx: int, target_team: String, target_idx: int) -> Array:
	var generated_hits = []

	# The datamine usually wraps these in an outer array [[...]], so grab index 0 if needed
	var dmg_array = attack_damage[0] if typeof(attack_damage[0]) == TYPE_ARRAY else attack_damage
	var frame_array = attack_frames[0] if typeof(attack_frames[0]) == TYPE_ARRAY else attack_frames

	for i in range(dmg_array.size()):
		var percent = float(dmg_array[i]) / 100.0
		var split_damage = int(max(1, raw_damage * percent))

		generated_hits.append({
			"frame_to_execute": frame_array[i],
			"damage": split_damage,
			"attacker_team": attacker_team,
			"attacker_index": attacker_idx,
			"target_team": target_team,
			"target_index": target_idx
		})

	return generated_hits
