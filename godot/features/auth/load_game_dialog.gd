extends PopupPanel

signal load_selected(username: String)
signal delete_requested(save_id: String, username: String)

const SaveListRowScene: PackedScene = preload("res://features/auth/SaveListRow.tscn")

@onready var saves_list: VBoxContainer = $VBox/Scroll/SavesList
@onready var empty_label: Label = $VBox/EmptyLabel
@onready var close_button: Button = $VBox/CloseButton


func _ready() -> void:
	close_button.pressed.connect(hide)


func refresh() -> void:
	for child in saves_list.get_children():
		child.queue_free()

	var saves: Array = AccountService.list_local_saves()
	# Sort by last_loaded_unix desc.
	saves.sort_custom(func(a, b):
		var a_ts: int = int(a.get("last_loaded_unix", a.get("created_at_unix", 0))) if a is Dictionary else 0
		var b_ts: int = int(b.get("last_loaded_unix", b.get("created_at_unix", 0))) if b is Dictionary else 0
		return a_ts > b_ts
	)

	var added: int = 0
	for entry_var in saves:
		if not (entry_var is Dictionary):
			continue
		var entry: Dictionary = entry_var
		if str(entry.get("id", "")).is_empty():
			continue
		var row: Node = SaveListRowScene.instantiate()
		saves_list.add_child(row)
		row.setup(entry)
		row.load_requested.connect(_on_row_load_requested)
		row.delete_requested.connect(_on_row_delete_requested)
		added += 1

	empty_label.visible = added == 0


func _on_row_load_requested(_save_id: String, username: String) -> void:
	hide()
	load_selected.emit(username)


func _on_row_delete_requested(save_id: String, username: String) -> void:
	delete_requested.emit(save_id, username)
