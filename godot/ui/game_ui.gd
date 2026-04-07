extends Control


func _ready():
	pass

func _on_world_map_pressed():
	UIManager.push("map_ui")

func _on_user_menu_pressed(id: int):
	if id == 0:
		UIManager.push("edit_profile_ui")
	elif id == 1:
		DataManager.logout()
		UIManager.set_root("login_ui")
