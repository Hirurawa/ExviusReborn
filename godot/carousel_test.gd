extends Control

@onready var left_button: TextureButton = $LeftButton
@onready var right_button: TextureButton = $RightButton
@onready var mask: Control = $Mask

var current_index: int = 0
var items: Array[Node] = []
var is_animating: bool = false # Prevents spam-clicking

func _ready() -> void:
	items = mask.get_children()
	
	left_button.pressed.connect(_on_left_pressed)
	right_button.pressed.connect(_on_right_pressed)
	
	# Hide all items except the first one, and reset their positions
	for i in range(items.size()):
		items[i].visible = (i == current_index)
		items[i].position.x = 0

func _on_left_pressed() -> void:
	if is_animating: return
	var next_index = current_index - 1
	if next_index < 0:
		next_index = items.size() - 1 
	
	slide_to(next_index, -1) # -1 means slide from the left

func _on_right_pressed() -> void:
	if is_animating: return
	var next_index = current_index + 1
	if next_index >= items.size():
		next_index = 0 
		
	slide_to(next_index, 1) # 1 means slide from the right

func slide_to(next_index: int, direction: int) -> void:
	is_animating = true
	
	var current_item = items[current_index]
	var next_item = items[next_index]
	
	# Position the new item completely off-screen in the direction it's coming from
	var slide_distance = mask.size.x
	next_item.position.x = slide_distance * direction
	next_item.visible = true
	
	# Create a parallel tween so both items move at the exact same time
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# Slide the current item out
	tween.tween_property(current_item, "position:x", -slide_distance * direction, 0.3)
	
	# Slide the next item in to position 0 (center)
	tween.tween_property(next_item, "position:x", 0, 0.3)
	
	# Once the animation finishes, clean up
	tween.chain().tween_callback(func():
		current_item.visible = false
		current_index = next_index
		is_animating = false
	)
