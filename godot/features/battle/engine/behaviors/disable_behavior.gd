class_name DisableBehavior
extends AilmentBehavior

## Ailments that stop the bearer from doing anything: the lasting stop and charm (the
## user chose charm as a plain disable, as the wiki describes it, not the FF "attacks
## its allies"), and paralysis, sleep and petrify, which build on this. The wiki says
## paralysis, stop and charm also stop the bearer from evading.

var _evades: bool


func _init(ailment_keys: PackedStringArray, lasting: bool = false, evades: bool = false) -> void:
	super(ailment_keys, lasting)
	_evades = evades


func control() -> int:
	return CONTROL_DISABLED


func prevents_evasion() -> bool:
	return not _evades
