class_name SkillGrant
extends RefCounted

## A skill a combatant may use for a while: op 100, "Enable X, Y for N turns" (GrantHandler).
## The engine keeps them in Combatant.grants and:
##   - counts turns down when the enemy phase begins: turn_count includes the cast
##     turn, so 2 from the unit's own action is "for one turn" (its next turn), and 1
##     from a counter in the enemy phase or a battle-start cast still reaches the next
##     player phase (a reading from who casts the turn_count 1 rows; the user's default,
##     2026-10-05);
##   - spends a use when an action whose command names the skill starts;
##   - replaces a grant of the same skill with the new one;
##   - ends them all on KO, and keeps them across waves, like buffs.
## The engine does not check whether a unit owns the skill a command names (it never
## has); BattleCommandMenu offers granted skills only while they are granted.

## turns_left / uses_left for no limit.
const UNLIMITED: int = -1
## turn_count from this many turns up has no time limit (9999, 99999, 999999 in the data).
const NO_TIME_LIMIT_FROM: int = 9999
## uses from this many up are unlimited (999, 9999, 99999).
const UNLIMITED_USES_FROM: int = 999

## BattleSkill.KIND_ABILITY or KIND_MAGIC.
var skill_kind: StringName = BattleSkill.KIND_ABILITY
var skill_id: String = ""
## Enemy phase starts left before it ends; UNLIMITED for none.
var turns_left: int = UNLIMITED
## Casts left; UNLIMITED for none.
var uses_left: int = UNLIMITED
## The skill whose effect granted it, and its caster's combatant id.
var source_skill_id: String = ""
var granted_by: int = -1


static func make(kind: StringName, id: String, turns: int, uses: int) -> SkillGrant:
	var grant := SkillGrant.new()
	grant.skill_kind = kind
	grant.skill_id = id
	grant.turns_left = turns
	grant.uses_left = uses
	return grant


## turns_left for an op 100 turn_count: -1 (and a missing slot), 9999 and up have no
## time limit.
static func turns_from(turn_count: int) -> int:
	return UNLIMITED if turn_count <= 0 or turn_count >= NO_TIME_LIMIT_FROM else turn_count


## uses_left for an op 100 uses slot: 0 (and a missing slot) and 999 and up are
## unlimited (none of the 7 rows with 0 mentions uses).
static func uses_from(uses: int) -> int:
	return UNLIMITED if uses <= 0 or uses >= UNLIMITED_USES_FROM else uses


## The key of Combatant.grants, the same as SkillHistory's.
func key() -> String:
	return SkillHistory.skill_key(skill_kind, skill_id)


func copy() -> SkillGrant:
	var grant: SkillGrant = make(skill_kind, skill_id, turns_left, uses_left)
	grant.source_skill_id = source_skill_id
	grant.granted_by = granted_by
	return grant


func describe() -> String:
	var turns: String = "no time limit" if turns_left == UNLIMITED else "%d turn(s)" % turns_left
	var uses: String = "unlimited uses" if uses_left == UNLIMITED else "%d use(s)" % uses_left
	return "%s %s, %s, %s" % [skill_kind, skill_id, turns, uses]
