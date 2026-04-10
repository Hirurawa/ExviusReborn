extends Control

@onready var email_input = $VBoxContainer/EmailInput
@onready var password_input = $VBoxContainer/PasswordInput
@onready var feedback_label = $VBoxContainer/FeedbackLabel
@onready var login_button = $VBoxContainer/HBoxContainer/LoginButton
@onready var go_to_register_button = $VBoxContainer/HBoxContainer/GoToRegisterButton

func _ready():
	login_button.pressed.connect(_on_login_button_pressed)
	go_to_register_button.pressed.connect(_on_go_to_register_button_pressed)
	DataManager.login_success.connect(_on_login_success)
	DataManager.login_failed.connect(_on_login_failed)

func _on_login_button_pressed():
	var email = email_input.text.strip_edges()
	var password = password_input.text.strip_edges()

	if email.is_empty() or password.is_empty():
		feedback_label.text = "Email and Password are required."
		return

	feedback_label.text = "Logging in..."
	DataManager.authenticate(email, password)

func _on_login_success():
	feedback_label.text = "Login successful!"
	UIManager.push("game_ui")

func _on_login_failed(error_code: int):
	feedback_label.text = "Login failed. Error code: %d" % error_code

func _on_go_to_register_button_pressed():
	UIManager.push("register_ui")
