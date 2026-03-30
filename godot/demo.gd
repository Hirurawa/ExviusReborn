extends Node2D


@onready var server_connection := $ServerConnection
@onready var debug_panel := $CanvasLayer/DebugPanel

func _ready() -> void:
	var email := "test@test.com"
	var password := "Password1"
	
	debug_panel.write_message("Authenticating user %s." % email)
	var result: int = await(server_connection.authenticate_async(email, password))
	
	if result == OK:
		debug_panel.write_message("SUCCESS")
	else:
		debug_panel.write_message("FAIL")
