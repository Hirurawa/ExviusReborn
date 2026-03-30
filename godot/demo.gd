extends Node2D


@onready var server_connection := $ServerConnection
@onready var debug_panel := $CanvasLayer/DebugPanel

@onready var login_ui := $CanvasLayer/LoginUI
@onready var register_ui := $CanvasLayer/RegisterUI
@onready var game_ui := $CanvasLayer/GameUI

@onready var login_email_input := $CanvasLayer/LoginUI/VBoxContainer/EmailInput
@onready var login_password_input := $CanvasLayer/LoginUI/VBoxContainer/PasswordInput
@onready var login_feedback_label := $CanvasLayer/LoginUI/VBoxContainer/FeedbackLabel

@onready var register_username_input := $CanvasLayer/RegisterUI/VBoxContainer/UsernameInput
@onready var register_email_input := $CanvasLayer/RegisterUI/VBoxContainer/EmailInput
@onready var register_password_input := $CanvasLayer/RegisterUI/VBoxContainer/PasswordInput
@onready var register_feedback_label := $CanvasLayer/RegisterUI/VBoxContainer/FeedbackLabel

@onready var login_button := $CanvasLayer/LoginUI/VBoxContainer/HBoxContainer/LoginButton
@onready var go_to_register_button := $CanvasLayer/LoginUI/VBoxContainer/HBoxContainer/GoToRegisterButton

@onready var register_button := $CanvasLayer/RegisterUI/VBoxContainer/HBoxContainer/RegisterButton
@onready var back_to_login_button := $CanvasLayer/RegisterUI/VBoxContainer/HBoxContainer/BackToLoginButton

@onready var edit_profile_ui := $CanvasLayer/EditProfileUI
@onready var edit_new_username_input := $CanvasLayer/EditProfileUI/VBoxContainer/NewUsernameInput
@onready var edit_feedback_label := $CanvasLayer/EditProfileUI/VBoxContainer/FeedbackLabel
@onready var edit_update_button := $CanvasLayer/EditProfileUI/VBoxContainer/HBoxContainer/UpdateButton
@onready var edit_cancel_button := $CanvasLayer/EditProfileUI/VBoxContainer/HBoxContainer/CancelButton

@onready var user_info_label := $CanvasLayer/GameUI/UserInfoLabel
@onready var user_menu_button := $CanvasLayer/GameUI/UserMenuButton

func _ready() -> void:
	login_button.pressed.connect(_on_login_button_pressed)
	go_to_register_button.pressed.connect(_on_go_to_register_button_pressed)
	register_button.pressed.connect(_on_register_button_pressed)
	back_to_login_button.pressed.connect(_on_back_to_login_button_pressed)

	edit_update_button.pressed.connect(_on_edit_update_button_pressed)
	edit_cancel_button.pressed.connect(_on_edit_cancel_button_pressed)

	user_menu_button.get_popup().id_pressed.connect(_on_user_menu_id_pressed)

func _on_user_menu_id_pressed(id: int) -> void:
	if id == 0:
		_on_edit_profile_pressed()
	elif id == 1:
		_on_logout_pressed()

func _on_edit_profile_pressed() -> void:
	game_ui.hide()
	edit_profile_ui.show()
	edit_new_username_input.text = ""
	edit_feedback_label.text = "Enter new username"

func _on_edit_cancel_button_pressed() -> void:
	edit_profile_ui.hide()
	game_ui.show()

func _on_edit_update_button_pressed() -> void:
	var new_username: String = edit_new_username_input.text.strip_edges()

	if new_username.is_empty():
		edit_feedback_label.text = "Username cannot be empty."
		return

	edit_feedback_label.text = "Updating profile..."
	debug_panel.write_message("Updating username to %s." % new_username)

	var result: int = await(server_connection.update_account_async(new_username))

	if result == OK:
		edit_feedback_label.text = "Update successful!"
		debug_panel.write_message("SUCCESS")
		edit_profile_ui.hide()
		game_ui.show()

		var account = await(server_connection.get_account_async())
		if account and account.user.username != "":
			user_info_label.text = "Welcome, " + account.user.username + "!"
	else:
		edit_feedback_label.text = "Update failed. Error code: %d" % result
		debug_panel.write_message("FAIL: %d" % result)

func _on_logout_pressed() -> void:
	server_connection.logout()
	game_ui.hide()
	login_ui.show()
	user_info_label.text = ""
	login_feedback_label.text = "Logged out successfully."
	debug_panel.write_message("User logged out.")

func _on_go_to_register_button_pressed() -> void:
	login_ui.hide()
	register_ui.show()

func _on_back_to_login_button_pressed() -> void:
	register_ui.hide()
	login_ui.show()

func _on_login_button_pressed() -> void:
	var email: String = login_email_input.text.strip_edges()
	var password: String = login_password_input.text.strip_edges()
	
	if email.is_empty() or password.is_empty():
		login_feedback_label.text = "Email and Password are required."
		return

	login_feedback_label.text = "Logging in..."
	debug_panel.write_message("Authenticating user %s." % email)

	var result: int = await(server_connection.authenticate_async(email, password))
	
	if result == OK:
		login_feedback_label.text = "Login successful!"
		debug_panel.write_message("SUCCESS")
		_transition_to_game(email)
	else:
		login_feedback_label.text = "Login failed. Error code: %d" % result
		debug_panel.write_message("FAIL: %d" % result)

func _on_register_button_pressed() -> void:
	var username: String = register_username_input.text.strip_edges()
	var email: String = register_email_input.text.strip_edges()
	var password: String = register_password_input.text.strip_edges()

	if username.is_empty() or email.is_empty() or password.is_empty():
		register_feedback_label.text = "Username, Email, and Password are required."
		return

	register_feedback_label.text = "Registering..."
	debug_panel.write_message("Registering user %s." % email)

	var result: int = await(server_connection.register_async(email, password, username))

	if result == OK:
		register_feedback_label.text = "Registration successful!"
		debug_panel.write_message("SUCCESS")
		_transition_to_game(email)
	else:
		register_feedback_label.text = "Registration failed. Error code: %d" % result
		debug_panel.write_message("FAIL: %d" % result)

func _transition_to_game(email: String) -> void:
	login_ui.hide()
	register_ui.hide()
	game_ui.show()
	user_info_label.text = "Fetching profile..."

	var account = await(server_connection.get_account_async())
	if account:
		if account.user.username != "":
			user_info_label.text = "Welcome, " + account.user.username + "!"
		else:
			user_info_label.text = "Welcome, " + email + "!"
	else:
		user_info_label.text = "Welcome!"
