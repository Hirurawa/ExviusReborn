extends ScrollContainer

signal world_map_pressed
signal espers_pressed
signal craft_pressed

@export var snap_duration: float = 0.2
@onready var button_row: HBoxContainer = %ButtonRow
@onready var world_map_button: TextureButton = $ButtonRow/WorldMap
@onready var espers_button: TextureButton = $ButtonRow/Espers
@onready var craft_button: TextureButton = $ButtonRow/Craft

var _is_dragging: bool = false

func _ready() -> void:
	world_map_button.pressed.connect(_on_world_map_pressed)
	espers_button.pressed.connect(_on_espers_pressed)
	craft_button.pressed.connect(_on_craft_pressed)

func _on_world_map_pressed() -> void:
	world_map_pressed.emit()

func _on_espers_pressed() -> void:
	espers_pressed.emit()

func _on_craft_pressed() -> void:
	craft_pressed.emit()

func _gui_input(event: InputEvent) -> void:
	# Detect when the user touches or lifts their finger/mouse
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			_is_dragging = true
		else:
			_is_dragging = false
			_snap_to_nearest_button()

func _snap_to_nearest_button() -> void:
	# 1. Find the current center point of the view
	var center_view_x = scroll_horizontal + (size.x / 2.0)
	
	var nearest_button: Control = null
	var min_distance = INF
	
	# 2. Loop through buttons to find which one is closest to the center
	for child in button_row.get_children():
		if not child is Control: continue
		
		# Calculate the center of this specific child
		var child_center_x = child.position.x + (child.size.x / 2.0)
		var distance = abs(child_center_x - center_view_x)
		
		if distance < min_distance:
			min_distance = distance
			nearest_button = child
			
	# 3. Calculate the exact scroll position needed to center that button
	if nearest_button:
		var target_scroll_x = nearest_button.position.x + (nearest_button.size.x / 2.0) - (size.x / 2.0)
		
		# Clamp it so it doesn't over-scroll past the edges
		var max_scroll = button_row.size.x - size.x
		target_scroll_x = clamp(target_scroll_x, 0, max_scroll)
		
		# 4. Tween the scroll bar for a buttery smooth slide
		var tween = create_tween()
		tween.tween_property(self, "scroll_horizontal", int(target_scroll_x), snap_duration)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_OUT)
