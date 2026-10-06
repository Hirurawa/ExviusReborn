class_name ParalysisBehavior
extends DisableBehavior

## Paralysis: the bearer does nothing and cannot evade. It ends with the battle (wiki);
## enemies roll to shake it off like any status ailment.


func _init() -> void:
	super(PackedStringArray(["PARALYSIS"]))


func persists_after_battle() -> bool:
	return false
