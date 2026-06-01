extends HBoxContainer

signal load_requested(save_id: String, username: String)
signal delete_requested(save_id: String, username: String)

@onready var name_label: Label = $InfoVBox/NameLabel
@onready var time_label: Label = $InfoVBox/TimeLabel
@onready var load_button: Button = $LoadButton
@onready var delete_button: Button = $DeleteButton

var save_id: String = ""
var username: String = ""


func _ready() -> void:
	load_button.pressed.connect(_on_load_pressed)
	delete_button.pressed.connect(_on_delete_pressed)


func setup(entry: Dictionary) -> void:
	save_id = str(entry.get("id", ""))
	username = str(entry.get("username", save_id))
	name_label.text = username
	var ts: int = int(entry.get("last_loaded_unix", entry.get("created_at_unix", 0)))
	if ts > 0:
		time_label.text = "Last played: %s" % Time.get_datetime_string_from_unix_time(ts, true)
	else:
		time_label.text = ""


func _on_load_pressed() -> void:
	load_requested.emit(save_id, username)


func _on_delete_pressed() -> void:
	delete_requested.emit(save_id, username)
