extends Node2D


@onready var server_connection := $ServerConnection
@onready var debug_panel := $CanvasLayer/DebugPanel

@onready var login_ui := $CanvasLayer/LoginUI
@onready var game_ui := $CanvasLayer/GameUI

@onready var username_input := $CanvasLayer/LoginUI/VBoxContainer/UsernameInput
@onready var email_input := $CanvasLayer/LoginUI/VBoxContainer/EmailInput
@onready var password_input := $CanvasLayer/LoginUI/VBoxContainer/PasswordInput
@onready var feedback_label := $CanvasLayer/LoginUI/VBoxContainer/FeedbackLabel

@onready var login_button := $CanvasLayer/LoginUI/VBoxContainer/HBoxContainer/LoginButton
@onready var register_button := $CanvasLayer/LoginUI/VBoxContainer/HBoxContainer/RegisterButton

@onready var user_info_label := $CanvasLayer/GameUI/UserInfoLabel

func _ready() -> void:
	login_button.pressed.connect(_on_login_button_pressed)
	register_button.pressed.connect(_on_register_button_pressed)

func _on_login_button_pressed() -> void:
	var email := email_input.text.strip_edges()
	var password := password_input.text.strip_edges()
	
	if email.is_empty() or password.is_empty():
		feedback_label.text = "Email and Password are required."
		return

	feedback_label.text = "Logging in..."
	debug_panel.write_message("Authenticating user %s." % email)

	var result: int = await(server_connection.authenticate_async(email, password))
	
	if result == OK:
		feedback_label.text = "Login successful!"
		debug_panel.write_message("SUCCESS")
		_transition_to_game()
	else:
		feedback_label.text = "Login failed. Error code: %d" % result
		debug_panel.write_message("FAIL: %d" % result)

func _on_register_button_pressed() -> void:
	var username := username_input.text.strip_edges()
	var email := email_input.text.strip_edges()
	var password := password_input.text.strip_edges()

	if username.is_empty() or email.is_empty() or password.is_empty():
		feedback_label.text = "Username, Email, and Password are required."
		return

	feedback_label.text = "Registering..."
	debug_panel.write_message("Registering user %s." % email)

	var result: int = await(server_connection.register_async(email, password, username))

	if result == OK:
		feedback_label.text = "Registration successful!"
		debug_panel.write_message("SUCCESS")
		_transition_to_game()
	else:
		feedback_label.text = "Registration failed. Error code: %d" % result
		debug_panel.write_message("FAIL: %d" % result)

func _transition_to_game() -> void:
	login_ui.hide()
	game_ui.show()
	user_info_label.text = "Fetching profile..."

	var account = await(server_connection.get_account_async())
	if account:
		if account.user.username != "":
			user_info_label.text = "Welcome, " + account.user.username + "!"
		else:
			user_info_label.text = "Welcome, " + email_input.text.strip_edges() + "!"
	else:
		user_info_label.text = "Welcome!"
