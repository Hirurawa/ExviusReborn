class_name AilmentBehavior
extends StatusBehavior

## Durations shared by every ailment. A status ailment (the wiki's term: poison ..
## petrify, zombie) is permanent on both sides; enemies shake it off with a roll at the
## start of each of their turns. A lasting effect (stop, charm, berserk) lasts the turns
## its skill gives instead, on both sides, and nobody rolls it off.

var _keys: PackedStringArray
var _lasting: bool


func _init(ailment_keys: PackedStringArray, lasting: bool = false) -> void:
	_keys = ailment_keys
	_lasting = lasting


func keys() -> PackedStringArray:
	return _keys


func turns_on(_engine: BattleEngine, _target: Combatant, data_turns: int) -> int:
	return data_turns if _lasting else -1


func recovers_by_roll() -> bool:
	return not _lasting
