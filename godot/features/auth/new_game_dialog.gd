extends AcceptDialog

signal created(username: String)

@onready var name_input: LineEdit = $VBox/NameInput
@onready var feedback_label: Label = $VBox/FeedbackLabel

var _busy: bool = false


func _ready() -> void:
	title = "New Game"
	ok_button_text = "Create"
	get_ok_button().pressed.connect(_on_confirm_pressed)
	# AcceptDialog auto-hides on confirmed; we want manual control so we can
	# keep it open on validation failure. We re-show in _on_confirm_pressed
	# if the input is invalid or creation fails.
	confirmed.connect(_on_confirmed_dummy)
	about_to_popup.connect(_on_about_to_popup)


func _on_about_to_popup() -> void:
	_busy = false
	name_input.text = ""
	feedback_label.text = ""
	name_input.editable = true
	get_ok_button().disabled = false
	name_input.grab_focus.call_deferred()


func _on_confirmed_dummy() -> void:
	# Intentionally empty — real work happens in _on_confirm_pressed so we can
	# branch on validation/async result.
	pass


func _on_confirm_pressed() -> void:
	if _busy:
		return
	var save_name: String = name_input.text.strip_edges()
	if save_name.is_empty():
		feedback_label.text = "Please enter a name."
		# Reopen because AcceptDialog will auto-hide after confirmed signal.
		call_deferred("popup_centered")
		return

	_busy = true
	name_input.editable = false
	get_ok_button().disabled = true
	feedback_label.text = "Creating new game..."

	var result: Dictionary = AccountService.start_new_local_game(save_name)
	_busy = false
	if not bool(result.get("success", false)):
		feedback_label.text = str(result.get("error_message", "Failed to create new game."))
		name_input.editable = true
		get_ok_button().disabled = false
		call_deferred("popup_centered")
		return

	created.emit(save_name)
