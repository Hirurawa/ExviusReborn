extends Control

@onready var add_friend_input = $VBoxContainer/AddFriendHBox/AddFriendInput
@onready var add_friend_button = $VBoxContainer/AddFriendHBox/AddFriendButton
@onready var friends_feedback_label = $VBoxContainer/FeedbackLabel
@onready var friends_list_container = $VBoxContainer/ScrollContainer/FriendsListContainer

func _ready():
	add_friend_button.pressed.connect(_on_add_friend_button_pressed)
	DataManager.friends_updated.connect(_on_friends_updated)
	DataManager.friend_action_result.connect(_on_friend_action_result)
	DataManager.list_friends()

func _on_add_friend_button_pressed() -> void:
	var username: String = add_friend_input.text.strip_edges()

	if username.is_empty():
		friends_feedback_label.text = "Username cannot be empty."
		return

	friends_feedback_label.text = "Sending friend request..."
	DataManager.add_friend(username)

func _on_friend_action_result(success: bool, message: String):
	if success:
		friends_feedback_label.text = "Action successful!"
		add_friend_input.text = ""
	else:
		friends_feedback_label.text = "Action failed: " + message

func _on_friends_updated(friends_list) -> void:
	for child in friends_list_container.get_children():
		child.queue_free()

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
		var friend = friend_obj
		var hbox := HBoxContainer.new()
		var label := Label.new()
		var state_str := "Unknown"

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
			delete_btn.pressed.connect(func(): DataManager.delete_friend(friend.user.username))
			hbox.add_child(delete_btn)
		elif friend.state == 1:
			var undo_btn := Button.new()
			undo_btn.text = "Undo"
			undo_btn.pressed.connect(func(): DataManager.delete_friend(friend.user.username))
			hbox.add_child(undo_btn)
		elif friend.state == 2:
			var accept_btn := Button.new()
			accept_btn.text = "Accept"
			accept_btn.pressed.connect(func(): DataManager.add_friend(friend.user.username))
			hbox.add_child(accept_btn)
			var decline_btn := Button.new()
			decline_btn.text = "Decline"
			decline_btn.pressed.connect(func(): DataManager.delete_friend(friend.user.username))
			hbox.add_child(decline_btn)

		friends_list_container.add_child(hbox)
