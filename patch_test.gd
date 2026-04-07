extends SceneTree

func _init():
	var file = FileAccess.open("res://assets/equipment-icons.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		print("Valid JSON: ", json != null)
		print("Has 1: ", json.has("1"))
	else:
		print("Could not load equipment-icons.json locally")
	quit()
