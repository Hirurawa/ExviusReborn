class_name SkillEffectWrapper
extends Node2D

var _delay: float = 0.0
var _emitter: EffekseerEmitter2D


func setup(effect_path: String, delay: float) -> void:
	_delay = delay
	if ResourceLoader.exists(effect_path):
		_emitter = EffekseerEmitter2D.new()
		_emitter.effect = load(effect_path)
		add_child(_emitter)
	else:
		print("Resource for effect not found: " + effect_path)


func _ready() -> void:
	if not is_instance_valid(_emitter):
		# The effect file is missing: nothing will ever play or finish.
		queue_free()
		return
	if _delay > 0.0:
		var tween = create_tween()
		tween.bind_node(self)
		tween.tween_callback(play_effect).set_delay(_delay)
	else:
		play_effect()


func play_effect() -> void:
	if is_instance_valid(_emitter):
		_emitter.play()
		
		if _emitter.has_user_signal("finished") or _emitter.has_signal("finished"):
			_emitter.connect("finished", _on_effect_finished)


func _on_effect_finished() -> void:
	queue_free()
