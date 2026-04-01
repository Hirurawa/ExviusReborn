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


@onready var stats_level_label := $CanvasLayer/GameUI/TopHeader/BottomRow/HBox/RankContainer/LevelLabel
@onready var stats_xp_label := $CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EXPContainer/ProgressBar/XPLabel
@onready var stats_xp_bar := $CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EXPContainer/ProgressBar
@onready var stats_xp_input := $CanvasLayer/GameUI/TopHeader/DebugXPContainer/XPInput
@onready var stats_add_xp_button := $CanvasLayer/GameUI/TopHeader/DebugXPContainer/AddXPButton

var current_level: int = 1
var current_xp: int = 0
@onready var user_info_label := $CanvasLayer/GameUI/TopHeader/TopRow/HBox/UserInfoLabel
@onready var user_menu_button := $CanvasLayer/GameUI/UserMenuButton

@onready var bottom_nav := $CanvasLayer/BottomNav
@onready var home_button := $CanvasLayer/BottomNav/HBox/HomeButton
@onready var friends_button := $CanvasLayer/BottomNav/HBox/FriendsButton
@onready var units_button := $CanvasLayer/BottomNav/HBox/UnitsButton
@onready var items_button := $CanvasLayer/BottomNav/HBox/ItemsButton
@onready var summon_button := $CanvasLayer/BottomNav/HBox/SummonButton

@onready var units_ui := $CanvasLayer/UnitsUI
@onready var units_list_container := $CanvasLayer/UnitsUI/VBoxContainer/ScrollContainer/UnitsListContainer

@onready var unit_detail_ui := $CanvasLayer/UnitDetailUI
@onready var unit_detail_back_button := $CanvasLayer/UnitDetailUI/VBoxContainer/TopBar/BackButton
@onready var unit_detail_name_label := $CanvasLayer/UnitDetailUI/VBoxContainer/TopBar/TitleBox/NameLabel
@onready var unit_detail_rarity_label := $CanvasLayer/UnitDetailUI/VBoxContainer/TopBar/TitleBox/InfoHBox/RarityLabel
@onready var unit_detail_level_label := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/LevelHBox/LevelLabel
@onready var unit_detail_next_xp_label := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/LevelHBox/NextXPLabel
@onready var unit_detail_hp_value := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/HPValue
@onready var unit_detail_mp_value := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/MPValue
@onready var unit_detail_atk_value := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/ATKValue
@onready var unit_detail_def_value := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/DEFValue
@onready var unit_detail_mag_value := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/MAGValue
@onready var unit_detail_spr_value := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/SPRValue
@onready var unit_detail_add_xp_button := $CanvasLayer/UnitDetailUI/VBoxContainer/ActionsHBox/AddXPButton
@onready var unit_detail_awaken_button := $CanvasLayer/UnitDetailUI/VBoxContainer/ActionsHBox/AwakenButton

@onready var items_ui := $CanvasLayer/ItemsUI
@onready var items_list_container := $CanvasLayer/ItemsUI/VBoxContainer/ScrollContainer/ItemsListContainer
@onready var add_potion_button := $CanvasLayer/ItemsUI/VBoxContainer/AddPotionButton

var game_data_units: Dictionary = {}
var game_data_items: Dictionary = {}
var game_data_weapons: Dictionary = {}

var owned_units_ids: Array = []
var owned_items: Array = []

@onready var friends_ui := $CanvasLayer/FriendsUI
@onready var add_friend_input := $CanvasLayer/FriendsUI/VBoxContainer/AddFriendHBox/AddFriendInput
@onready var add_friend_button := $CanvasLayer/FriendsUI/VBoxContainer/AddFriendHBox/AddFriendButton
@onready var friends_feedback_label := $CanvasLayer/FriendsUI/VBoxContainer/FeedbackLabel
@onready var friends_list_container := $CanvasLayer/FriendsUI/VBoxContainer/ScrollContainer/FriendsListContainer

@onready var summon_ui := $CanvasLayer/SummonUI
@onready var summon_perform_button := $CanvasLayer/SummonUI/VBoxContainer/PerformSummonButton
@onready var summon_overlay := $CanvasLayer/SummonUI/SummonOverlay
@onready var summon_results_list := $CanvasLayer/SummonUI/SummonOverlay/VBoxContainer/ScrollContainer/ResultsListContainer
@onready var summon_close_overlay_button := $CanvasLayer/SummonUI/SummonOverlay/VBoxContainer/CloseOverlayButton

func _ready() -> void:

	stats_add_xp_button.pressed.connect(_on_add_xp_button_pressed)
	login_button.pressed.connect(_on_login_button_pressed)
	go_to_register_button.pressed.connect(_on_go_to_register_button_pressed)
	register_button.pressed.connect(_on_register_button_pressed)
	back_to_login_button.pressed.connect(_on_back_to_login_button_pressed)

	edit_update_button.pressed.connect(_on_edit_update_button_pressed)
	edit_cancel_button.pressed.connect(_on_edit_cancel_button_pressed)

	user_menu_button.get_popup().id_pressed.connect(_on_user_menu_id_pressed)

	home_button.pressed.connect(_on_home_button_pressed)
	friends_button.pressed.connect(_on_friends_button_pressed)
	add_friend_button.pressed.connect(_on_add_friend_button_pressed)

	units_button.pressed.connect(_on_units_button_pressed)

	items_button.pressed.connect(_on_items_button_pressed)
	add_potion_button.pressed.connect(_on_add_potion_button_pressed)

	summon_button.pressed.connect(_on_summon_button_pressed)
	summon_perform_button.pressed.connect(_on_summon_perform_button_pressed)
	summon_close_overlay_button.pressed.connect(_on_summon_close_overlay_button_pressed)

	unit_detail_back_button.pressed.connect(_on_unit_detail_back_button_pressed)

func _update_stats_ui() -> void:
	var required_xp = current_level * 100
	stats_level_label.text = "%d" % current_level

	if required_xp > 0:
		stats_xp_bar.max_value = required_xp
		stats_xp_bar.value = current_xp

	stats_xp_label.text = "%d / %d" % [current_xp, required_xp]

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

func _hide_all_ui() -> void:
	game_ui.hide()
	friends_ui.hide()
	units_ui.hide()
	items_ui.hide()
	summon_ui.hide()
	edit_profile_ui.hide()
	unit_detail_ui.hide()

func _on_home_button_pressed() -> void:
	_hide_all_ui()
	game_ui.show()
	bottom_nav.show()

func _on_edit_profile_pressed() -> void:
	_hide_all_ui()
	bottom_nav.hide()
	edit_profile_ui.show()
	edit_new_username_input.text = ""
	edit_feedback_label.text = "Enter new username"

func _on_edit_cancel_button_pressed() -> void:
	edit_profile_ui.hide()
	game_ui.show()
	bottom_nav.show()

func _on_friends_button_pressed() -> void:
	_hide_all_ui()
	friends_ui.show()
	friends_feedback_label.text = ""
	add_friend_input.text = ""
	_refresh_friends_list()

func _on_units_button_pressed() -> void:
	_hide_all_ui()
	units_ui.show()
	_refresh_units_list()

func _on_items_button_pressed() -> void:
	_hide_all_ui()
	items_ui.show()
	_refresh_items_list()

func _on_add_potion_button_pressed() -> void:
	var result = await server_connection.add_item_async("item_001", 1)
	if result.has("error"):
		print("Failed to add potion: ", result.error)
	else:
		owned_items = await server_connection.read_player_items_async()
		_refresh_items_list()

func _refresh_items_list() -> void:
	for child in items_list_container.get_children():
		items_list_container.remove_child(child)
		child.queue_free()

	if owned_items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No items owned."
		items_list_container.add_child(empty_label)
		return

	for item in owned_items:
		if not item is Dictionary:
			continue

		var item_id = item.get("item_id", "")
		var item_data: Dictionary = game_data_items.get(item_id, {})

		var label := Label.new()
		label.text = "%s x%d" % [item_data.get("name", "Unknown Item"), item.get("quantity", 0)]
		label.add_theme_font_size_override("font_size", 18)
		items_list_container.add_child(label)

func _on_summon_button_pressed() -> void:
	_hide_all_ui()
	summon_ui.show()

func _on_summon_close_overlay_button_pressed() -> void:
	summon_overlay.hide()

func _on_summon_perform_button_pressed() -> void:
	if game_data_units.is_empty():
		return

	var summoned_units = await server_connection.summon_units_async(3)
	owned_units_ids.append_array(summoned_units)

	for child in summon_results_list.get_children():
		summon_results_list.remove_child(child)
		child.queue_free()

	for unit_inst in summoned_units:
		var unit_id = unit_inst.get("unit_id", "")
		var unit_data: Dictionary = game_data_units.get(unit_id, {})
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label := Label.new()
		name_label.text = "Name: %s" % unit_data.get("name", "Unknown")
		name_label.add_theme_font_size_override("font_size", 18)
		vbox.add_child(name_label)

		var level_label := Label.new()
		level_label.text = "Level: %d (XP: %d) | Rarity: %d★" % [
			unit_inst.get("level", 1),
			unit_inst.get("xp", 0),
			unit_inst.get("current_rarity", 1)
		]
		vbox.add_child(level_label)

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

		summon_results_list.add_child(vbox)

	summon_overlay.show()


func _refresh_units_list() -> void:
	for child in units_list_container.get_children():
		units_list_container.remove_child(child)
		child.queue_free()

	if owned_units_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No units owned."
		units_list_container.add_child(empty_label)
		return

	for unit_inst in owned_units_ids:
		if not unit_inst is Dictionary:
			continue

		var unit_id = unit_inst.get("unit_id", "")
		var unit_data: Dictionary = game_data_units.get(unit_id, {})

		var grid_item := Button.new()
		grid_item.custom_minimum_size = Vector2(0, 80)
		grid_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid_item.text = unit_data.get("name", "Unknown")
		grid_item.pressed.connect(_show_unit_detail.bind(unit_inst))

		units_list_container.add_child(grid_item)

func _show_unit_detail(unit_inst: Dictionary) -> void:
	_hide_all_ui()
	unit_detail_ui.show()

	var unit_id = unit_inst.get("unit_id", "")
	var unit_data: Dictionary = game_data_units.get(unit_id, {})
	var base_stats = unit_data.get("base_stats", {})

	unit_detail_name_label.text = unit_data.get("name", "Unknown")

	var rarity = unit_inst.get("current_rarity", 1)
	var stars = ""
	for i in range(rarity):
		stars += "★"
	unit_detail_rarity_label.text = stars

	var rarity_max_levels = {
		1: 15,
		2: 30,
		3: 40,
		4: 60,
		5: 80,
		6: 100,
		7: 120
	}

	var level = unit_inst.get("level", 1)
	var max_level = rarity_max_levels.get(rarity, 15)
	unit_detail_level_label.text = "Lvl %d/%d" % [level, max_level]

	var xp = unit_inst.get("xp", 0)
	var required_xp = level * 1000 # placeholder required xp logic
	var next_xp = required_xp - xp
	if next_xp < 0:
		next_xp = 0
	unit_detail_next_xp_label.text = "next %d" % next_xp

	unit_detail_hp_value.text = str(int(base_stats.get("hp", 0)))
	unit_detail_mp_value.text = str(int(base_stats.get("mp", 0)))
	unit_detail_atk_value.text = str(int(base_stats.get("atk", 0)))
	unit_detail_def_value.text = str(int(base_stats.get("def", 0)))

	# Fallback values for missing stats based on user instruction
	unit_detail_mag_value.text = "0"
	unit_detail_spr_value.text = "0"

	# Disconnect previously bound signals to avoid duplicate calls
	for connection in unit_detail_add_xp_button.pressed.get_connections():
		unit_detail_add_xp_button.pressed.disconnect(connection["callable"])

	for connection in unit_detail_awaken_button.pressed.get_connections():
		unit_detail_awaken_button.pressed.disconnect(connection["callable"])

	var instance_id = unit_inst.get("instance_id", "")
	unit_detail_add_xp_button.pressed.connect(_on_unit_add_xp_pressed.bind(instance_id))
	unit_detail_awaken_button.pressed.connect(_on_unit_awaken_pressed.bind(instance_id))

func _on_unit_detail_back_button_pressed() -> void:
	unit_detail_ui.hide()
	units_ui.show()

func _on_unit_add_xp_pressed(instance_id: String) -> void:
	var result = await server_connection.add_unit_xp_async(instance_id, 1000)
	if result.has("error"):
		print("Failed to add XP: ", result.error)
	else:
		# Refresh full units list
		owned_units_ids = await server_connection.read_player_units_async()
		_refresh_units_list()
		# Re-render detail page with updated data if it's currently showing
		if unit_detail_ui.visible:
			for unit in owned_units_ids:
				if unit.get("instance_id") == instance_id:
					_show_unit_detail(unit)
					break

func _on_unit_awaken_pressed(instance_id: String) -> void:
	var result = await server_connection.awaken_unit_async(instance_id)
	if result.has("error"):
		print("Failed to awaken: ", result.error)
	else:
		# Refresh full units list
		owned_units_ids = await server_connection.read_player_units_async()
		_refresh_units_list()
		# Re-render detail page with updated data if it's currently showing
		if unit_detail_ui.visible:
			for unit in owned_units_ids:
				if unit.get("instance_id") == instance_id:
					_show_unit_detail(unit)
					break

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
		bottom_nav.show()

		var account = await(server_connection.get_account_async())
		if account and account.user.username != "":
			user_info_label.text = account.user.username
	else:
		edit_feedback_label.text = "Update failed. Error code: %d" % result

func _on_logout_pressed() -> void:
	server_connection.logout()
	_hide_all_ui()
	bottom_nav.hide()
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
	bottom_nav.show()

	var stats = await server_connection.read_player_stats_async()
	current_level = int(stats.get("level", 1))
	current_xp = int(stats.get("xp", 0))
	_update_stats_ui()

	owned_units_ids = await server_connection.read_player_units_async()
	owned_items = await server_connection.read_player_items_async()

	var game_data = await server_connection.get_game_data_async()
	if game_data:
		game_data_units = game_data.get("units", {})
		game_data_items = game_data.get("items", {})
		game_data_weapons = game_data.get("weapons", {})

	user_info_label.text = "Fetching profile..."

	var account = await(server_connection.get_account_async())
	if account:
		if account.user.username != "":
			user_info_label.text = account.user.username 
		else:
			user_info_label.text = email
	else:
		user_info_label.text = "Welcome!"
