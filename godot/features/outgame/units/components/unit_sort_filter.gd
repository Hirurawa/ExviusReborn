extends Control

@onready var back_button: TextureButton = $VBoxContainer/sort_filter_top_tab_bg/sort_filter_top_btn_back

@onready var sort_view = $VBoxContainer/MarginContainer/Sort
@onready var filter_view = $VBoxContainer/MarginContainer/ScrollContainer

@onready var sort_tab_btn = $VBoxContainer/sort_filter_top_tab_bg/sort_filter_top_tab_sort
@onready var filter_tab_btn = $VBoxContainer/sort_filter_top_tab_bg/sort_filter_top_tab_filter

var active_filters: Dictionary = {
	"elements": [],
	"ailments": [],
	"rarities": []
}

@onready var elements_grid = $VBoxContainer/MarginContainer/ScrollContainer/Filter/ElemAtk/Buttons
@onready var ailments_grid = $VBoxContainer/MarginContainer/ScrollContainer/Filter/Ailment/Buttons
@onready var rarities_grid = $VBoxContainer/MarginContainer/ScrollContainer/Filter/Rarity/Buttons

func _ready() -> void:
	# Connect your custom tab buttons
	sort_tab_btn.pressed.connect(_on_sort_tab_pressed)
	filter_tab_btn.pressed.connect(_on_filter_tab_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	# Default state: Show sort, hide filter
	_on_sort_tab_pressed()
	
	# Map the categories to their physical UI containers
	var filter_groups = {
		"elements": elements_grid,
		"ailments": ailments_grid,
		"rarities": rarities_grid
	}
	
	# Loop through the dictionary
	for category in filter_groups.keys():
		var container = filter_groups[category]
		
		for btn in container.get_children():
			if btn is BaseButton:
				# Bind BOTH the category string and the button itself!
				btn.toggled.connect(_on_any_filter_toggled.bind(category, btn))

func _on_back_pressed() -> void:
	UIManager.pop()

func _on_sort_tab_pressed() -> void:
	sort_view.visible = true
	filter_view.visible = false

func _on_filter_tab_pressed() -> void:
	sort_view.visible = false
	filter_view.visible = true

# The universal function now receives the category directly
func _on_any_filter_toggled(is_pressed: bool, category: String, btn: BaseButton) -> void:
	
	# Get the node's name and make it lowercase just to be safe 
	var value = btn.name.to_lower()
	
	# If dealing with numbers (like rarity "5"), Godot handles string/int conversions easily, 
	# but you can cast it if your unit data requires integers:
	if category == "rarities":
		value = value.to_int() 
		
	# Apply to the state dictionary
	if is_pressed:
		active_filters[category].append(value)
	else:
		active_filters[category].erase(value)
		
	print("Active Filters updated: ", active_filters)
