extends Node2D


@onready var server_connection := $ServerConnection

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


@onready var stats_level_label := $CanvasLayer/GameUI/StatsContainer/LevelLabel
@onready var stats_xp_label := $CanvasLayer/GameUI/StatsContainer/XPLabel
@onready var stats_xp_input := $CanvasLayer/GameUI/StatsContainer/HBoxContainer/XPInput
@onready var stats_add_xp_button := $CanvasLayer/GameUI/StatsContainer/HBoxContainer/AddXPButton

var current_level: int = 1
var current_xp: int = 0
@onready var user_info_label := $CanvasLayer/GameUI/UserInfoLabel
@onready var user_menu_button := $CanvasLayer/GameUI/UserMenuButton
@onready var friends_button := $CanvasLayer/GameUI/FriendsButton
@onready var units_button := $CanvasLayer/GameUI/UnitsButton

@onready var units_ui := $CanvasLayer/UnitsUI
@onready var units_list_container := $CanvasLayer/UnitsUI/VBoxContainer/ScrollContainer/UnitsListContainer
@onready var units_back_home_button := $CanvasLayer/UnitsUI/VBoxContainer/BackHomeButton

var game_data_units: Dictionary = {}
var game_data_items: Dictionary = {}
var game_data_weapons: Dictionary = {}

@onready var friends_ui := $CanvasLayer/FriendsUI
@onready var add_friend_input := $CanvasLayer/FriendsUI/VBoxContainer/AddFriendHBox/AddFriendInput
@onready var add_friend_button := $CanvasLayer/FriendsUI/VBoxContainer/AddFriendHBox/AddFriendButton
@onready var friends_feedback_label := $CanvasLayer/FriendsUI/VBoxContainer/FeedbackLabel
@onready var friends_list_container := $CanvasLayer/FriendsUI/VBoxContainer/ScrollContainer/FriendsListContainer
@onready var back_home_button := $CanvasLayer/FriendsUI/VBoxContainer/BackHomeButton

func _ready() -> void:

	stats_add_xp_button.pressed.connect(_on_add_xp_button_pressed)
	login_button.pressed.connect(_on_login_button_pressed)
	go_to_register_button.pressed.connect(_on_go_to_register_button_pressed)
	register_button.pressed.connect(_on_register_button_pressed)
	back_to_login_button.pressed.connect(_on_back_to_login_button_pressed)

	edit_update_button.pressed.connect(_on_edit_update_button_pressed)
	edit_cancel_button.pressed.connect(_on_edit_cancel_button_pressed)

	user_menu_button.get_popup().id_pressed.connect(_on_user_menu_id_pressed)

	friends_button.pressed.connect(_on_friends_button_pressed)
	add_friend_button.pressed.connect(_on_add_friend_button_pressed)
	back_home_button.pressed.connect(_on_back_home_button_pressed)

	units_button.pressed.connect(_on_units_button_pressed)
	units_back_home_button.pressed.connect(_on_units_back_home_button_pressed)

func _update_stats_ui() -> void:
	var required_xp = current_level * 100
	stats_level_label.text = "Level: %d" % current_level
	stats_xp_label.text = "XP: %d / %d" % [current_xp, required_xp]

func _on_add_xp_button_pressed() -> void:
	var xp_to_add: int = stats_xp_input.text.to_int()
	if xp_to_add <= 0:
		return

	current_xp += xp_to_add

	var required_xp = current_level * 100
	while current_xp >= required_xp:
		current_xp -= required_xp
		current_level += 1
		required_xp = current_level * 100

	_update_stats_ui()
	stats_xp_input.text = ""

	await server_connection.write_player_stats_async(current_level, current_xp)

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

func _on_friends_button_pressed() -> void:
	game_ui.hide()
	friends_ui.show()
	friends_feedback_label.text = ""
	add_friend_input.text = ""
	_refresh_friends_list()

func _on_back_home_button_pressed() -> void:
	friends_ui.hide()
	game_ui.show()

func _on_units_button_pressed() -> void:
	game_ui.hide()
	units_ui.show()
	_refresh_units_list()

func _on_units_back_home_button_pressed() -> void:
	units_ui.hide()
	game_ui.show()

func _refresh_units_list() -> void:
	for child in units_list_container.get_children():
		units_list_container.remove_child(child)
		child.queue_free()

	if game_data_units.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No units found."
		units_list_container.add_child(empty_label)
		return

	for unit_id in game_data_units:
		var unit_data: Dictionary = game_data_units[unit_id]
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label := Label.new()
		name_label.text = "Name: %s" % unit_data.get("name", "Unknown")
		name_label.add_theme_font_size_override("font_size", 18)
		vbox.add_child(name_label)

		var stats_label := Label.new()
		var base_stats = unit_data.get("base_stats", {})
		var stats_text = "HP: %s | MP: %s | ATK: %s | DEF: %s" % [
			base_stats.get("hp", "?"),
			base_stats.get("mp", "?"),
			base_stats.get("atk", "?"),
			base_stats.get("def", "?")
		]
		stats_label.text = stats_text
		vbox.add_child(stats_label)

		var separator := HSeparator.new()
		vbox.add_child(separator)

		units_list_container.add_child(vbox)

func _on_add_friend_button_pressed() -> void:
	var username: String = add_friend_input.text.strip_edges()

	if username.is_empty():
		friends_feedback_label.text = "Username cannot be empty."
		return

	friends_feedback_label.text = "Adding friend..."

	var result: int = await(server_connection.add_friends_async(username))

	if result == OK:
		friends_feedback_label.text = "Friend request sent/accepted!"
		add_friend_input.text = ""
		_refresh_friends_list()
	elif result == ERR_UNAUTHORIZED:
		friends_feedback_label.text = "Not authorized."
	elif result == 3: # Invalid argument, usually means username not found or trying to add self
		friends_feedback_label.text = "User not found or invalid."
	else:
		friends_feedback_label.text = "Failed to add friend. Code: %d" % result

func _refresh_friends_list() -> void:
	for child in friends_list_container.get_children():
		friends_list_container.remove_child(child)
		child.queue_free()

	var friends_list: NakamaAPI.ApiFriendList = await(server_connection.list_friends_async())

	if friends_list == null:
		var err_label := Label.new()
		err_label.text = "Failed to load friends."
		friends_list_container.add_child(err_label)
		return

	if friends_list.friends.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No friends yet."
		friends_list_container.add_child(empty_label)
		return

	for friend_obj in friends_list.friends:
		var friend: NakamaAPI.ApiFriend = friend_obj as NakamaAPI.ApiFriend
		var hbox := HBoxContainer.new()
		var label := Label.new()
		var state_str := "Unknown"

		# State: 0 = Friend, 1 = Invite sent, 2 = Invite received, 3 = Blocked
		match friend.state:
			0: state_str = "Friend"
			1: state_str = "Invite Sent"
			2: state_str = "Invite Received"
			3: state_str = "Blocked"

		label.text = "%s (%s)" % [friend.user.username, state_str]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)

		if friend.state == 0:
			var delete_btn := Button.new()
			delete_btn.text = "Delete"
			delete_btn.pressed.connect(_on_delete_friend_pressed.bind(friend.user.username))
			hbox.add_child(delete_btn)
		elif friend.state == 1:
			var undo_btn := Button.new()
			undo_btn.text = "Undo"
			undo_btn.pressed.connect(_on_undo_request_pressed.bind(friend.user.username))
			hbox.add_child(undo_btn)
		elif friend.state == 2:
			var accept_btn := Button.new()
			accept_btn.text = "Accept"
			accept_btn.pressed.connect(_on_accept_request_pressed.bind(friend.user.username))
			hbox.add_child(accept_btn)
			var decline_btn := Button.new()
			decline_btn.text = "Decline"
			decline_btn.pressed.connect(_on_decline_request_pressed.bind(friend.user.username))
			hbox.add_child(decline_btn)

		friends_list_container.add_child(hbox)

func _on_delete_friend_pressed(username: String) -> void:
	friends_feedback_label.text = "Deleting friend..."
	var result: int = await(server_connection.delete_friends_async(username))
	if result == OK:
		friends_feedback_label.text = "Friend deleted."
		_refresh_friends_list()
	else:
		friends_feedback_label.text = "Failed to delete friend. Code: %d" % result

func _on_undo_request_pressed(username: String) -> void:
	friends_feedback_label.text = "Undoing friend request..."
	var result: int = await(server_connection.delete_friends_async(username))
	if result == OK:
		friends_feedback_label.text = "Friend request undone."
		_refresh_friends_list()
	else:
		friends_feedback_label.text = "Failed to undo request. Code: %d" % result

func _on_accept_request_pressed(username: String) -> void:
	friends_feedback_label.text = "Accepting friend request..."
	var result: int = await(server_connection.add_friends_async(username))
	if result == OK:
		friends_feedback_label.text = "Friend request accepted."
		_refresh_friends_list()
	else:
		friends_feedback_label.text = "Failed to accept request. Code: %d" % result

func _on_decline_request_pressed(username: String) -> void:
	friends_feedback_label.text = "Declining friend request..."
	var result: int = await(server_connection.delete_friends_async(username))
	if result == OK:
		friends_feedback_label.text = "Friend request declined."
		_refresh_friends_list()
	else:
		friends_feedback_label.text = "Failed to decline request. Code: %d" % result


func _on_edit_update_button_pressed() -> void:
	var new_username: String = edit_new_username_input.text.strip_edges()

	if new_username.is_empty():
		edit_feedback_label.text = "Username cannot be empty."
		return

	edit_feedback_label.text = "Updating profile..."

	var result: int = await(server_connection.update_account_async(new_username))

	if result == OK:
		edit_feedback_label.text = "Update successful!"
		edit_profile_ui.hide()
		game_ui.show()

		var account = await(server_connection.get_account_async())
		if account and account.user.username != "":
			user_info_label.text = "Welcome, " + account.user.username + "!"
	else:
		edit_feedback_label.text = "Update failed. Error code: %d" % result

func _on_logout_pressed() -> void:
	server_connection.logout()
	game_ui.hide()
	login_ui.show()
	user_info_label.text = ""
	login_feedback_label.text = "Logged out successfully."

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

	var result: int = await(server_connection.authenticate_async(email, password))
	
	if result == OK:
		login_feedback_label.text = "Login successful!"
		_transition_to_game(email)
	else:
		login_feedback_label.text = "Login failed. Error code: %d" % result

func _on_register_button_pressed() -> void:
	var username: String = register_username_input.text.strip_edges()
	var email: String = register_email_input.text.strip_edges()
	var password: String = register_password_input.text.strip_edges()

	if username.is_empty() or email.is_empty() or password.is_empty():
		register_feedback_label.text = "Username, Email, and Password are required."
		return

	register_feedback_label.text = "Registering..."

	var result: int = await(server_connection.register_async(email, password, username))

	if result == OK:
		register_feedback_label.text = "Registration successful!"
		_transition_to_game(email)
	else:
		register_feedback_label.text = "Registration failed. Error code: %d" % result

func _transition_to_game(email: String) -> void:
	login_ui.hide()
	register_ui.hide()
	game_ui.show()

	var stats = await server_connection.read_player_stats_async()
	current_level = int(stats.get("level", 1))
	current_xp = int(stats.get("xp", 0))
	_update_stats_ui()

	var game_data = await server_connection.get_game_data_async()
	if game_data:
		game_data_units = game_data.get("units", {})
		game_data_items = game_data.get("items", {})
		game_data_weapons = game_data.get("weapons", {})

	user_info_label.text = "Fetching profile..."

	var account = await(server_connection.get_account_async())
	if account:
		if account.user.username != "":
			user_info_label.text = "Welcome, " + account.user.username + "!"
		else:
			user_info_label.text = "Welcome, " + email + "!"
	else:
		user_info_label.text = "Welcome!"
