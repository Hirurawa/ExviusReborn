extends RefCounted
class_name EffectSpawner

## Effect frame offsets are in frames (1/60 s), the unit of effectFrames.
const FRAMES_PER_SECOND: float = 60.0

var _host: Node


func _init(host: Node) -> void:
	_host = host


## Plays a skill's effects (its record's `effect_frames`) in the middle of `container`,
## each starting its frame offset into the cast. `speed` is the battle's speed, so the
## effects keep pace with the hits at 2x or 4x.
func spawn(effect_data: Array, container: Control, speed: float = 1.0) -> void:
	if container == null or _host == null or not is_instance_valid(_host):
		return
	for group in effect_data:
		for eff in group:
			var effect_names = GameDatabase.get_effect_data(eff.get("effect_id"))
			var delay: float = float(eff.get("frame_offset", 0)) / FRAMES_PER_SECOND / maxf(speed, 0.01)
			for e in effect_names:
				var name = e.replace(".bmb", ".efkefc")
				var path = "res://assets/battle_effect/" + name
				var wrapper = SkillEffectWrapper.new()
				wrapper.setup(path, delay)
				container.add_child(wrapper)
				wrapper.position = container.size / 2
