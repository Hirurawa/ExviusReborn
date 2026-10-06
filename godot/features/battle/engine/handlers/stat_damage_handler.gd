class_name StatDamageHandler
extends DamageHandler

## Every damage opcode that runs through DamageFormula, and basic attacks. Each type is
## one row of SPECS, so a new variant is a new row rather than a new branch:
##   kind            DamageFormula.Kind, or KIND_FROM_ATTACK_TYPE (drain: the skill's
##                   attack type picks physical, magic or hybrid)
##   modifier        param key of the modifier (default "modifier")
##   magic_modifier  param key of a hybrid's magic modifier
##   ignore          param key (or "slot:N" for an unnamed slot) of the DEF / SPR
##                   piercing percent, with ignore_sign turning it positive
##   miss            param key of a chance, rolled per target, that every hit misses
##   hp_cost         param key of the caster's HP cost, percent of max HP
##   drain           param key of the percent of damage dealt the caster recovers
##   spr_modifier    evoke damage: param key of the SPR part's modifier (default: the
##                   modifier, so one modifier serves both stats)
##   ratio           evoke damage: param key of the [MAG, SPR] percent shares ("50:50");
##                   without one, BattleRules.esper_attack_mag_ratio_pct and the rest
##   consecutive     a stacking ability (72, 126, 1007): the modifier is the wiki's base
##                   plus a stack modifier per stack the action casts with
##                   (SkillHistory.stacked_modifier, BattleAction.stacks)
##
## Evoke damage (124) and the espers' own attacks (79, 80, 94) use the wiki's evoke
## formula (DamageFormula.Kind.EVOKE), the espers' with a 50:50 ratio, which their data
## lacks (the user's rule, 2026-10-02). Their skills' attack type is fixed (4): only
## general mitigation, no evasion, cover, killers, dual wield or weapon elements.
##
## Not modelled yet: the "instant KO" half of 112, 113 and 94 (death resistance is not
## in the data we read; those always deal damage), the race bonus of 22 and 23 (the data
## gives only the race), and the `max` slot of 102 and 103.

const KIND_FROM_ATTACK_TYPE: int = -1

const SPECS: Dictionary = {
	"PHYSICAL_DAMAGE": {"kind": DamageFormula.Kind.PHYSICAL},
	"MAGIC_DAMAGE": {"kind": DamageFormula.Kind.MAGIC},
	"HYBRID_DAMAGE": {"kind": DamageFormula.Kind.HYBRID, "modifier": "phys_modifier", "magic_modifier": "mag_modifier"},
	"PHYSICAL_DAMAGE_IGNORE_COVER": {"kind": DamageFormula.Kind.PHYSICAL, "ignore": "ignore_def", "ignore_sign": -1},
	"MAGIC_DAMAGE_IGNORE_SPR": {"kind": DamageFormula.Kind.MAGIC, "ignore": "ignore", "ignore_sign": 1},
	"DEF_DAMAGE": {"kind": DamageFormula.Kind.DEF_BASED},
	"SPR_DAMAGE": {"kind": DamageFormula.Kind.SPR_BASED},
	"PHYSICAL_DAMAGE_TRIBE": {"kind": DamageFormula.Kind.PHYSICAL},
	"MAGICAL_DAMAGE_TRIBE": {"kind": DamageFormula.Kind.MAGIC},
	"NUM_PHYS_ATTACK": {"kind": DamageFormula.Kind.PHYSICAL},
	"PHYS_ATTACK_CHANCE_TO_MISS": {"kind": DamageFormula.Kind.PHYSICAL, "miss": "miss_chance"},
	"HP_SAC_PHYS_DAMAGE": {"kind": DamageFormula.Kind.PHYSICAL, "hp_cost": "hp_sac_pct"},
	"DEATH_OR_PHYS_DAMAGE": {"kind": DamageFormula.Kind.PHYSICAL, "ignore": "slot:3", "ignore_sign": -1},
	"DEATH_OR_MAG_DAMAGE": {"kind": DamageFormula.Kind.MAGIC},
	"DRAIN": {"kind": KIND_FROM_ATTACK_TYPE, "drain": "pct"},
	"EVOKE_DAMAGE": {"kind": DamageFormula.Kind.EVOKE, "spr_modifier": "modifier_2", "ratio": "stat_ratio"},
	"ESPER_PHYS_DAMAGE": {"kind": DamageFormula.Kind.EVOKE},
	"ESPER_MAG_DAMAGE": {"kind": DamageFormula.Kind.EVOKE},
	"ESPER_KO_OR_DAMAGE": {"kind": DamageFormula.Kind.EVOKE},
	# 72 deals magic damage whatever its attack type (13 of its 15 rows with a physical
	# attack type say magic damage); 1007's two rows are physical (attack type 1).
	"CONSECUTIVE_MAG_DAMAGE": {"kind": DamageFormula.Kind.MAGIC, "consecutive": true},
	"CONSECUTIVE_PHYS_DAMAGE": {"kind": DamageFormula.Kind.PHYSICAL, "consecutive": true},
	"CONSECUTIVE_DAMAGE_V3": {"kind": DamageFormula.Kind.PHYSICAL, "consecutive": true},
}


func handled_types() -> PackedStringArray:
	return PackedStringArray(SPECS.keys())


func amount_for(engine: BattleEngine, action: BattleAction, effect: SkillEffect, actor: Combatant, target: Combatant) -> float:
	var spec: Dictionary = SPECS[effect.type]
	var modifier: float = effect.param_float(str(spec.get("modifier", "modifier")), 100.0)
	if bool(spec.get("consecutive", false)):
		modifier = SkillHistory.stacked_modifier(effect, action.stacks)
	var req: DamageFormula.Request = DamageFormula.request(
		actor, target, damage_kind(action, effect), modifier / 100.0, hit_elements(action, effect, actor)
	)
	req.magic_modifier = effect.param_float(str(spec.get("magic_modifier", "modifier")), 100.0) / 100.0
	if int(spec["kind"]) == DamageFormula.Kind.EVOKE:
		req.spr_modifier = effect.param_float(str(spec.get("spr_modifier", spec.get("modifier", "modifier"))), 100.0) / 100.0
		var shares: Vector2 = _evoke_shares(effect, spec, engine.rules)
		req.mag_ratio = shares.x
		req.spr_ratio = shares.y
	if spec.has("ignore"):
		req.defense_ignore = clampf(_param(effect, str(spec["ignore"])) * float(spec.get("ignore_sign", 1)) / 100.0, 0.0, 1.0)
	req.skill_ids = PackedStringArray([action.skill.id])
	if action.command != null and action.command.skill_id != "" and action.command.skill_id != action.skill.id:
		req.skill_ids.append(action.command.skill_id)
	req.opcode = effect.opcode
	req.is_limit_burst = action.skill.kind == BattleSkill.KIND_LIMIT_BURST
	req.atk_left_out = DualWield.atk_left_out(actor, action)
	return DamageFormula.compute(req, engine.rules, engine.rng).amount


## Physical damage that ignores part of DEF (21, and 112's piercing slot) goes past
## cover; SPR piercing does not (wiki).
func ignores_cover(effect: SkillEffect) -> bool:
	var spec: Dictionary = SPECS[effect.type]
	if not spec.has("ignore") or int(spec["kind"]) != DamageFormula.Kind.PHYSICAL:
		return false
	return _param(effect, str(spec["ignore"])) * float(spec.get("ignore_sign", 1)) > 0.0


func miss_reason_for(engine: BattleEngine, _action: BattleAction, effect: SkillEffect, _actor: Combatant, _target: Combatant) -> StringName:
	var spec: Dictionary = SPECS[effect.type]
	if not spec.has("miss"):
		return &""
	var chance: float = effect.param_float(str(spec["miss"]))
	return &"missed" if chance > 0.0 and engine.rng.randf() * 100.0 < chance else &""


func before_hits(engine: BattleEngine, action: BattleAction, effect: SkillEffect, actor: Combatant) -> void:
	var spec: Dictionary = SPECS[effect.type]
	if spec.has("hp_cost"):
		var cost: int = floori(float(actor.max_hp) * effect.param_float(str(spec["hp_cost"])) / 100.0)
		engine.spend_hp(actor, cost, action)


func damage_kind(action: BattleAction, effect: SkillEffect) -> int:
	var kind: int = int(SPECS[effect.type]["kind"])
	if kind != KIND_FROM_ATTACK_TYPE:
		return kind
	match action.skill.attack_type:
		BattleSkill.ATTACK_MAGIC:
			return DamageFormula.Kind.MAGIC
		BattleSkill.ATTACK_HYBRID:
			return DamageFormula.Kind.HYBRID
	return DamageFormula.Kind.PHYSICAL


func drain_pct(effect: SkillEffect) -> int:
	var spec: Dictionary = SPECS[effect.type]
	return int(effect.param_float(str(spec["drain"]))) if spec.has("drain") else 0


## Evoke damage's [MAG, SPR] shares as fractions: the effect's ratio param ([50, 50] from
## "50:50"), or the rules' default for the espers' own attacks, which carry none.
static func _evoke_shares(effect: SkillEffect, spec: Dictionary, rules: BattleRules) -> Vector2:
	var ratio: Variant = effect.params.get(str(spec.get("ratio", "")))
	if ratio is Array and (ratio as Array).size() >= 2:
		return Vector2(float(ratio[0]) / 100.0, float(ratio[1]) / 100.0)
	var mag_pct: int = clampi(rules.esper_attack_mag_ratio_pct, 0, 100)
	return Vector2(float(mag_pct) / 100.0, float(100 - mag_pct) / 100.0)


## A named param, or "slot:N" for a positional one the schema leaves unnamed.
static func _param(effect: SkillEffect, key: String) -> float:
	if key.begins_with("slot:"):
		var index: int = int(key.trim_prefix("slot:"))
		if index < effect.raw_params.size() and typeof(effect.raw_params[index]) in [TYPE_INT, TYPE_FLOAT]:
			return float(effect.raw_params[index])
		return 0.0
	return effect.param_float(key)
