extends ScrollContainer

@export var snap_duration: float = 0.2

var current_index: int = 0
var item_width: float = 0.0


func _ready() -> void:
	set_meta("touch_drag_keep_stop", true)
	# Wait one frame for the layout to build before grabbing sizes
	await get_tree().process_frame
	
	# Since only one item fits at a time, the item width is the container's width
	item_width = size.x 

func _gui_input(event: InputEvent) -> void:
	# Trigger the snap when the touch or mouse click is released
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if not event.pressed:
			snap_to_closest()

func snap_to_closest() -> void:
	if item_width == 0:
		return
		
	# Divide current scroll by width and round to find the nearest whole item
	current_index = round(scroll_horizontal / item_width)
	
	# Calculate the exact pixel position that item starts at
	var target_scroll = current_index * item_width
	
	# Smoothly animate the container to that exact position
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scroll_horizontal", target_scroll, snap_duration)
