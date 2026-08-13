extends RefCounted
class_name MonsterAIState

## The mutable half of the monster AI: one instance per spawned monster, holding the
## state its script reads and writes. MonsterAIScript is the immutable compiled
## script; MonsterAIRuntime walks the two together.
##
## STATE LIFETIMES. These are not guesses -- they were established by simulating
## Intangir (401011000) against its documented fight, which pins both halves:
##
##   flg / flg2      TURN-SCOPED. The banks are cleared when the monster's turn ends,
##                   and the writes of the rule that ENDS the turn are applied after
##                   that clear, so only those carry into the next turn. Intangir
##                   keeps "am I asleep" (flg1) alive exactly this way -- every one of
##                   its turn_end rules writes flg1=1 -- while its counter-attack
##                   chain flags (flg11-18) reset so each chain can run again next
##                   turn. Had the banks persisted, Intangir's first magic counter
##                   would leave flg13 set and rule 12 would turn_end forever after;
##                   had the clear happened at turn START instead, flg1 would never
##                   survive and it would re-cast Drifting Off every turn.
##   fire_counts     BATTLE-SCOPED. Backs `limited_act:N` ("this rule may fire at most
##                   N times"), which is the ONLY cross-turn persistence a script
##                   gets. Intangir's four threshold rules all use limited_act:1, so
##                   the counter must be per-rule: a single shared latch would let
##                   rule 1 firing on turn 1 block both Meteor thresholds forever.
##   acts_this_turn  TURN-SCOPED. Doubles as counter 1 -- see MonsterAIRuntime's
##                   handling of flg_cntup_act.
##
## Flags are absent-means-off. A script may test a flag that nothing ever writes
## (Intangir rule 20 tests flg8, which its own script never sets -- almost certainly
## an editing slip in the source data) and that has to read OFF, not warn.

## The monster this state belongs to. Informational; the runtime takes the compiled
## script separately so a state can be re-pointed at a re-compiled script.
var monster_id: String = ""

## Flag bank 1 (`flg_on` / `flg_off`, ids 1-30) as id -> value. Absent = 0 = OFF.
var flg: Dictionary = {}
## Flag bank 2 (`flg2_on` / `flg2_off`). Ids are sparse over 1-110, hence a
## Dictionary rather than a sized array.
var flg2: Dictionary = {}

## Actions taken in the current turn, 0-based. Also the value of counter 1, which
## `flg_cntup_act:1,N` tests: the first action of a turn matches N=0.
var acts_this_turn: int = 0
## Turns this monster has begun. Informational / for logging.
var turns_taken: int = 0
## Set once the turn is finished; the runtime stops handing out actions.
var turn_over: bool = true

## ruleOrder -> times that rule has fired this battle. Never cleared.
var fire_counts: Dictionary = {}
## ruleOrder -> true for rules already fired in the current turn. A rule may only
## fire once per turn, which is what bounds the turn walk -- see MonsterAIRuntime.
var fired_this_turn: Dictionary = {}

## Probability rolls come from here. Assign a seeded RandomNumberGenerator to make a
## battle reproducible (tests rely on this); one is created on first use otherwise.
var rng: RandomNumberGenerator = null


func _init(monster_id_in: String = "") -> void:
	monster_id = monster_id_in


## Starts a fresh turn. Does NOT clear the flag banks -- that happened when the
## previous turn ended, so that turn's final writes are still standing.
func begin_turn() -> void:
	acts_this_turn = 0
	turns_taken += 1
	turn_over = false
	fired_this_turn.clear()


## Ends the turn: clears both banks, then applies `ending_rule`'s writes so they
## survive into the next turn. Pass {} when the turn ended without a rule firing
## (nothing matched, or the action cap tripped), which clears the banks outright.
func end_turn(ending_rule: Dictionary = {}) -> void:
	flg.clear()
	flg2.clear()
	if not ending_rule.is_empty():
		apply_writes(ending_rule)
	turn_over = true


## Applies a fired rule's flag writes to both banks.
func apply_writes(rule: Dictionary) -> void:
	for write in rule.get("flg_writes", []):
		flg[int(write.get("id", 0))] = int(write.get("value", 0))
	for write in rule.get("flg2_writes", []):
		flg2[int(write.get("id", 0))] = int(write.get("value", 0))


## Bank-1 flag value; 0 when never written.
func flag(id: int) -> int:
	return int(flg.get(id, 0))


## Bank-2 flag value; 0 when never written.
func flag2(id: int) -> int:
	return int(flg2.get(id, 0))


## Times the rule at `rule_order` has fired this battle. Read by `limited_act:N`.
func fire_count(rule_order: int) -> int:
	return int(fire_counts.get(rule_order, 0))


## Records that the rule at `rule_order` fired.
func record_fire(rule_order: int) -> void:
	fire_counts[rule_order] = fire_count(rule_order) + 1
	fired_this_turn[rule_order] = true


## True when the rule at `rule_order` has already fired in the current turn and so
## may not fire again until the next one.
func fired_this_turn_already(rule_order: int) -> bool:
	return fired_this_turn.has(rule_order)


## A 0-100 roll for a rule's probability check.
func roll_percent() -> float:
	return _ensure_rng().randf() * 100.0


## A random index into a list of `count` items; -1 when the list is empty.
func roll_index(count: int) -> int:
	return -1 if count <= 0 else _ensure_rng().randi_range(0, count - 1)


func _ensure_rng() -> RandomNumberGenerator:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return rng


## Compact one-line state dump for battle logs.
func describe() -> String:
	return "turn %d act %d flg=%s flg2=%s%s" % [
		turns_taken, acts_this_turn, flg, flg2, "  (turn over)" if turn_over else "",
	]
