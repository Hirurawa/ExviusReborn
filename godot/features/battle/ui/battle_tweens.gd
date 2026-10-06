class_name BattleTweens
extends RefCounted

## Tweens both battle fields use on their sprites. A sprite keeps its running tweens in
## metas ("shake_tween", "fade_tween") so a new one can stop the old, and its resting x
## in "orig_x" so a shake always returns to the same place.

const SHAKE_OFFSET: float = 10.0
const SHAKE_STEP_SECONDS: float = 0.05


## A quick back-and-forth on a hit; a new hit restarts it.
static func shake(node: Control) -> void:
	kill(node, "shake_tween")
	var home_x: float = orig_x(node)
	var tween: Tween = node.create_tween()
	node.set_meta("shake_tween", tween)
	tween.tween_property(node, "position:x", home_x - SHAKE_OFFSET, SHAKE_STEP_SECONDS)
	tween.tween_property(node, "position:x", home_x + SHAKE_OFFSET, SHAKE_STEP_SECONDS)
	tween.tween_property(node, "position:x", home_x, SHAKE_STEP_SECONDS)


## Stops the tween kept in `node`'s meta `key`, if it is still running.
static func kill(node: Node, key: String) -> void:
	if node.has_meta(key):
		var tween: Variant = node.get_meta(key)
		if tween is Tween and (tween as Tween).is_valid():
			(tween as Tween).kill()


## The node's resting x, remembered the first time it moves.
static func orig_x(node: Control) -> float:
	if not node.has_meta("orig_x"):
		node.set_meta("orig_x", node.position.x)
	return float(node.get_meta("orig_x"))
