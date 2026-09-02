extends RefCounted
class_name EffectSpawner


var _host: Node


func _init(host: Node) -> void:
	_host = host


func spawn(effect_data: Array, container: Control) -> void:
	if container == null or _host == null or not is_instance_valid(_host):
		return
	#print("Effect:")
	for group in effect_data:
		#print("Group:")
		for eff in group:
			#print("frame: " + str(eff.get("frame_offset")) + " - id: " + str(eff.get("effect_id")))
			#print(GameDatabase.get_effect_data(eff.get("effect_id")))
			pass
	
	#var cura_test = EffekseerEmitter2D.new()
	#cura_test.effect = ResourceLoader.load("res://assets/models/release_candidate.efkefc")
	#cura_test.position = Vector2(100, 100)
	#container.add_child(cura_test)
	#cura_test.play()
	
	pass
