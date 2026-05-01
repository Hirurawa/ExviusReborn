extends Control

const INTRO_MISSION_ID: String = "1110100"

@onready var username_input: LineEdit = $VBoxContainer/UsernameInput
@onready var email_input: LineEdit = $VBoxContainer/EmailInput
@onready var password_input: LineEdit = $VBoxContainer/PasswordInput
@onready var feedback_label: Label = $VBoxContainer/FeedbackLabel
@onready var register_button: Button = $VBoxContainer/HBoxContainer/RegisterButton
@onready var back_to_login_button: Button = $VBoxContainer/HBoxContainer/BackToLoginButton

func _ready() -> void:
	register_button.pressed.connect(_on_register_button_pressed)
	back_to_login_button.pressed.connect(_on_back_to_login_button_pressed)
	DataManager.register_success.connect(_on_register_success)
	DataManager.register_failed.connect(_on_register_failed)

func _on_register_button_pressed() -> void:
	var username: String = username_input.text.strip_edges()
	var email: String = email_input.text.strip_edges()
	var password: String = password_input.text.strip_edges()

	if username.is_empty() or email.is_empty() or password.is_empty():
		feedback_label.text = "Username, Email, and Password are required."
		return

	feedback_label.text = "Registering..."
	DataManager.register(email, password, username)

func _on_register_success() -> void:
	feedback_label.text = "Registration successful!"
	UIManager.push("game_ui")

	var mission_result: Dictionary = await DataManager.request_start_mission(INTRO_MISSION_ID)
	if mission_result.get("success", false) == true:
		UIManager.push("combat_ui", {"mission_id": INTRO_MISSION_ID})
	else:
		push_warning("Intro mission failed to start after registration: %s" % mission_result.get("error", mission_result.get("error_message", "Unknown error")))

func _on_register_failed(error_code: int) -> void:
	feedback_label.text = "Registration failed. Error code: %d" % error_code

func _on_back_to_login_button_pressed() -> void:
	UIManager.pop()
