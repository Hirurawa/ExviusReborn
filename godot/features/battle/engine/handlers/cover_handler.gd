class_name CoverHandler
extends StatusHandler

## Effects that make a combatant cover its allies: a COVER status on the coverer, which
## CoverTracker reads when an opponent's attack is declared.
##   96 AOE_COVER  on each target, who covers: every ally (all_allies 1), or any one
##                 ally (0: two rows, one for male allies only). phys_mag 1 physical, 2
##                 magic, 0 both (missing: physical, as both rows say).
##   118 ST_COVER  on the caster, covering the ally it targets (physical_only 1 takes
##                 physical attacks only, 0 both).
## The pct_chance / chance_pct slot is the chance to cover, not to land: the status
## always lands. Statuses with the same key replace each other whatever their values,
## so a unit holds one AoE cover at a time (wiki: the most recent of a physical and a
## magic AoE cover wins).

const PHYS_MAG_SLOT: int = 8


func handled_types() -> PackedStringArray:
	return PackedStringArray(["AOE_COVER", "ST_COVER"])


func schedule(engine: BattleEngine, action: BattleAction, effect: SkillEffect, targets: Array[Combatant]) -> void:
	var actor: Combatant = engine.combatant(action.actor_id)
	if actor == null:
		return
	for target in targets:
		var bearer: Combatant = actor if effect.type == "ST_COVER" else target
		var hit: ScheduledHit = new_hit(action, effect, bearer)
		hit.payload = {"statuses": [{"status": cover_status(engine, effect, target), "chance": 100}]}
		engine.schedule_hit(hit, effect.hit_frames[0])


## The COVER status `effect` puts on its bearer; `target` is the effect's target (the
## ally an ST_COVER protects).
func cover_status(engine: BattleEngine, effect: SkillEffect, target: Combatant) -> BattleStatus:
	var physical: bool = true
	var magic: bool = true
	var chance_key: String = "chance_pct"
	var key: String = "st"
	var protects: int = -1
	var condition: int = CoverTracker.CONDITION_ANY
	if effect.type == "AOE_COVER":
		chance_key = "pct_chance"
		key = "aoe" if effect.param_float("all_allies") != 0.0 else "st"
		condition = int(effect.param_float("condition"))
		var mode: int = _int(effect.raw_params[PHYS_MAG_SLOT]) if effect.raw_params.size() > PHYS_MAG_SLOT else 1
		physical = mode != 2
		magic = mode != 1
	else:
		protects = target.id
		magic = effect.param_float("physical_only") == 0.0
	return BattleStatus.make(BattleStatus.COVER, key, int(effect.param_float(chance_key)), _turns(engine, effect), {
		"mit_min": int(effect.param_float("dmg_reduce_min")),
		"mit_max": int(effect.param_float("dmg_reduce_max")),
		"physical": physical,
		"magic": magic,
		"protects": protects,
		"condition": condition,
	})
