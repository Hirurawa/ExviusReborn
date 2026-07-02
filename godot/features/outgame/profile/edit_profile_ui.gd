extends Control

@onready var new_username_input: LineEdit = $VBoxContainer/NewUsernameInput
@onready var feedback_label: Label = $VBoxContainer/FeedbackLabel
@onready var update_button: Button = $VBoxContainer/HBoxContainer/UpdateButton
@onready var cancel_button: Button = $VBoxContainer/HBoxContainer/CancelButton

func _ready() -> void:
	update_button.pressed.connect(_on_update_button_pressed)
	cancel_button.pressed.connect(_on_cancel_button_pressed)

func _on_update_button_pressed() -> void:
	var new_username: String = new_username_input.text.strip_edges()
	if new_username.is_empty():
		feedback_label.text = "Username cannot be empty."
		return

	feedback_label.text = "Updating profile..."
	var success: bool = AccountService.update_account(new_username)
	if success:
		feedback_label.text = "Update successful!"
		UIManager.pop()
	else:
		feedback_label.text = "Update failed."

func _on_cancel_button_pressed() -> void:
	UIManager.pop()
