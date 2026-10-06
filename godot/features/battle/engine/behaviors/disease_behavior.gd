class_name DiseaseBehavior
extends AilmentBehavior

## Disease: ATK, DEF, MAG and SPR drop by BattleRules.disease_stat_pct of their raw
## base, on top of any breaks (wiki: "stacks with Break abilities"). The percent is
## stored as the status value when it lands. HP and MP are left alone.

const STATS: PackedStringArray = ["ATK", "DEF", "MAG", "SPR"]


func _init() -> void:
	super(PackedStringArray(["DISEASE"]))


func stat_percent(status: BattleStatus, stat_name: String) -> int:
	return status.value if STATS.has(stat_name) else 0


func prepare(engine: BattleEngine, _target: Combatant, status: BattleStatus) -> void:
	status.value = -engine.rules.disease_stat_pct
