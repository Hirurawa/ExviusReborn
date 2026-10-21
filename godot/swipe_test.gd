extends HBoxContainer

@onready var left_button: TextureButton = $LeftButton
@onready var right_button: TextureButton = $RightButton
@onready var item_container: CenterContainer = $ItemContainer

var current_index: int = 0
var items: Array[Node] = []

func _ready() -> void:
	# Gather all the items inside the container
	items = item_container.get_children()
	
	# Connect the button signals
	left_button.pressed.connect(_on_left_pressed)
	right_button.pressed.connect(_on_right_pressed)
	
	# Initialize the display
	update_display()

func _on_left_pressed() -> void:
	current_index -= 1
	# Wrap around to the last item if we go below zero
	if current_index < 0:
		current_index = items.size() - 1 
		
	update_display()

func _on_right_pressed() -> void:
	current_index += 1
	# Wrap around to the first item if we exceed the array
	if current_index >= items.size():
		current_index = 0 
		
	update_display()

func update_display() -> void:
	# Loop through all items and only show the one that matches the current index
	for i in range(items.size()):
		items[i].visible = (i == current_index)
