class_name EffectProcessor

static func calculate_raw_damage(modifier: float, caster_stat: int, target_stat: int) -> int:
	# Basic placeholder math: (Stat * Modifier)
	var raw = (caster_stat * modifier) - (target_stat * 0.5)
	return int(max(1, raw)) # Ensure at least 1 damage

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
