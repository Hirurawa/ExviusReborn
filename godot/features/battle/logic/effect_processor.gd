class_name EffectProcessor

static func generate_effect_payloads(effect_type: String, raw_amount: int, attack_damage: Array, attack_frames: Array, caster: Dictionary, target: Dictionary, extra_data: Dictionary = {}) -> Array:
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
			"target_index": target.get("index", 0)
		}
		
		for key in extra_data.keys():
			payload[key] = extra_data[key]

		generated_payloads.append(payload)
		
		if effect_type in ["BUFF", "DEBUFF"]:
			break 

	return generated_payloads
