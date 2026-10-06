extends Control

@export var unit_portrait_scene: PackedScene

@onready var back_button: TextureButton = $UnitNamebgChara/BackButton

@onready var search_input: LineEdit = $VBoxContainer/ScrollContainer/VBoxContainer/SearchInput

@onready var bottom_bar: Control = $VBoxContainer/BottomBar
@onready var toggle_mode_btn = $ToggleModeButton
@onready var sort_dropdown: OptionButton = $SortDropdown
@onready var sort_dir_btn: Button = $SortDirectionButton
@onready var scroll_container = $VBoxContainer/ScrollContainer
@onready var grid_container = $VBoxContainer/ScrollContainer/VBoxContainer/GridContainer
@onready var sort_filter = $SortFilter

var current_search_text: String = ""
var current_mode: GridMode
var player_roster: Array 


func _ready() -> void:
	bottom_bar.get_node("ClearButton").pressed.connect(_on_clear_pressed)
	bottom_bar.get_node("OkButton").pressed.connect(_on_ok_pressed)
	back_button.pressed.connect(_on_back_pressed)
	sort_filter.pressed.connect(_on_sort_filter_pressed)
	toggle_mode_btn.pressed.connect(_on_toggle_mode_pressed)
	sort_dropdown.item_selected.connect(_on_sort_selected)
	sort_dir_btn.pressed.connect(_on_sort_dir_pressed)
	search_input.text_changed.connect(_on_search_text_changed)


func init_scene(params: Dictionary) -> void:
	if not is_node_ready():
		await ready
	
	player_roster = UnitService.owned_units_ids
	
	var starting_mode = params.get("mode", ModeView.new())
	set_mode(starting_mode)


func set_mode(new_mode: GridMode) -> void:
	current_mode = new_mode
	bottom_bar.visible = current_mode.uses_bottom_bar()
	
	sort_dropdown.clear()
	var sort_keys = current_mode.sort_options.keys()
	
	for i in range(sort_keys.size()):
		var sort_name = sort_keys[i]
		sort_dropdown.add_item(sort_name)
		
		if sort_name == current_mode.active_sort_name:
			sort_dropdown.select(i)
	
	if current_mode is ModeSell:
		toggle_mode_btn.text = "Cancel Selling"
		toggle_mode_btn.visible = true
	elif current_mode is ModeView:
		toggle_mode_btn.text = "Sell Units"
		toggle_mode_btn.visible = true
	else:
		toggle_mode_btn.visible = false
	
	update_sort_direction_ui()
	refresh_grid()


func _on_sort_selected(index: int) -> void:
	var selected_sort_name = sort_dropdown.get_item_text(index)
	
	current_mode.active_sort_name = selected_sort_name
	
	refresh_grid()


func _on_toggle_mode_pressed() -> void:
	if current_mode is ModeView:
		set_mode(ModeSell.new())
	elif current_mode is ModeSell:
		set_mode(ModeView.new())


func _on_search_text_changed(new_text: String) -> void:
	current_search_text = new_text
	refresh_grid()


func refresh_grid() -> void:
	var filtered = current_mode.filter_units(player_roster)
	
	for child in grid_container.get_children():
		child.queue_free()
	
	if not current_search_text.is_empty():
		filtered = filtered.filter(func(unit):
			return current_search_text.to_lower() in unit.unitName.to_lower()
		)
		
	var sorted = current_mode.sort_units(filtered)
	
	if current_mode.wants_remove_button():
		var remove_btn = TextureButton.new()
		remove_btn.texture_normal = ResourceLoader.load("res://assets/ui/common/remove_mini.tres")
		remove_btn.texture_pressed = ResourceLoader.load("res://assets/ui/common/remove_mini2.tres")
		# Connect to the strategy's new handle_remove function
		remove_btn.pressed.connect(func(): current_mode.handle_selection({}, self))
		
		grid_container.add_child(remove_btn)
	
	for unit in sorted:
		var portrait = unit_portrait_scene.instantiate()
		grid_container.add_child(portrait)
		portrait.setup(unit)
		portrait.unit_selected.connect(_on_unit_selected)
	
	if current_search_text.is_empty():
		hide_search_bar()
	
	refresh_selection_visuals()


func hide_search_bar() -> void:
	await get_tree().process_frame
	scroll_container.scroll_vertical = int(search_input.size.y)


func _on_unit_selected(unit_data) -> void:
	current_mode.handle_selection(unit_data, self)


func _on_back_pressed() -> void:
	UIManager.pop()


func _on_clear_pressed() -> void:
	if current_mode.has_method("clear_selection"):
		current_mode.clear_selection(self)


func _on_ok_pressed() -> void:
	if current_mode.has_method("on_ok_pressed"):
		current_mode.on_ok_pressed(self)


func _on_sort_filter_pressed() -> void:
	UIManager.push("unit_sort_filter")


func show_sell_confirmation(selected_units) -> void:
	var ids = selected_units.map(func(u): return u.instance_id)
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.dialog_text = "Sell %d unit(s)?" % [selected_units.size()]
	dialog.title = "Sell Units"
	dialog.confirmed.connect(func():
		UnitService.sell_units(ids)
		player_roster = UnitService.owned_units_ids
		refresh_grid()
		)
	add_child(dialog)
	dialog.popup_centered()


func refresh_selection_visuals() -> void:
	if "selected_units" in current_mode:
		for child in grid_container.get_children():
			if child.has_method("set_selected") and "current_unit" in child:
				var is_selected = child.current_unit in current_mode.selected_units
				child.set_selected(is_selected)


func _on_sort_dir_pressed() -> void:
	current_mode.is_descending = not current_mode.is_descending
	
	update_sort_direction_ui()
	refresh_grid()


func update_sort_direction_ui() -> void:
	if current_mode.is_descending:
		sort_dir_btn.text = "↓"
	else:
		sort_dir_btn.text = "↑"
