class_name StatusBehaviorRegistry
extends RefCounted

## Maps ailment keys to the behaviours that make them do something, as EffectRegistry
## maps opcodes to handlers: effect handlers put statuses on combatants, behaviours act
## while they last. The AWAY kind has its own behaviour, whatever its key. Any other
## status (a buff, a break, an unknown ailment key) gets the no-op StatusBehavior.
## Behaviours are stateless, so one registry is shared by every battle;
## BattleStatus.behavior() looks up here, which lets Combatant answer can_act() and
## stat() without an engine.

static var _shared: StatusBehaviorRegistry = null

var _by_key: Dictionary = {}
var _default := StatusBehavior.new()
var _away := AwayBehavior.new()


static func shared() -> StatusBehaviorRegistry:
	if _shared == null:
		_shared = create_default()
	return _shared


## One behaviour per ailment key, status ailments first (in Combatant.AILMENTS order),
## then zombie and the lasting effects.
static func create_default() -> StatusBehaviorRegistry:
	var registry := StatusBehaviorRegistry.new()
	registry.register(PoisonBehavior.new())
	registry.register(BlindBehavior.new())
	registry.register(SleepBehavior.new())
	registry.register(SilenceBehavior.new())
	registry.register(ParalysisBehavior.new())
	registry.register(ConfusionBehavior.new())
	registry.register(DiseaseBehavior.new())
	registry.register(PetrifyBehavior.new())
	registry.register(ZombieBehavior.new())
	registry.register(DisableBehavior.new(PackedStringArray(["STOP", "CHARM"]), true))
	registry.register(BerserkBehavior.new())
	return registry


func register(behavior: StatusBehavior) -> void:
	for key in behavior.keys():
		_by_key[key] = behavior


func behavior_for(kind: StringName, key: String) -> StatusBehavior:
	if kind == BattleStatus.AILMENT:
		return _by_key.get(key, _default)
	if kind == BattleStatus.AWAY:
		return _away
	return _default


## Every ailment key with a behaviour, in registration order.
func ailment_keys() -> PackedStringArray:
	return PackedStringArray(_by_key.keys())
