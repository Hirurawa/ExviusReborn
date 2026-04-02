import re

with open('godot/demo.gd', 'r') as f:
    content = f.read()

# We need to do two things for the items.
# 1. Update the shop static potion to load its icon dynamically based on game_data_items.
# 2. Update the Items UI to also show the icon? The user said "add icons to the items... The attached picture contains the layout for the shop. place the 'desc_short' under the name and instead of 'Details' the button should say 'Buy'".
# They explicitly mentioned the Shop layout. It's unclear if they want icons on the inventory Items list too, but it says "add icons to the items... The attached picture contains the layout for the shop".
# So at the very least, in the shop, we must load the icon for the Potion.
# And we should probably apply a similar layout to the Items page, or maybe just "add icons to the items" means in general.
# Let's add icons to the inventory items list too, since they said "add icons to the items", plural.

items_list_func = '''func _refresh_items_list() -> void:
	for child in items_list_container.get_children():
		items_list_container.remove_child(child)
		child.queue_free()

	if owned_items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No items owned."
		items_list_container.add_child(empty_label)
		return

	for item in owned_items:
		if not item is Dictionary:
			continue

		var item_id = item.get("item_id", "")
		var item_data: Dictionary = game_data_items.get(item_id, {})

		var hbox := HBoxContainer.new()
		items_list_container.add_child(hbox)

		var icon_name = item_data.get("icon", "")
		if icon_name != "":
			var tex_rect := TextureRect.new()
			var tex = load("res://assets/items/" + icon_name)
			if tex:
				tex_rect.texture = tex
				tex_rect.custom_minimum_size = Vector2(40, 40)
				tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			hbox.add_child(tex_rect)

		var label := Label.new()
		label.text = "%s x%d" % [item_data.get("name", "Unknown Item"), item.get("quantity", 0)]
		label.add_theme_font_size_override("font_size", 18)
		hbox.add_child(label)'''

content = re.sub(
    r'func _refresh_items_list\(\) -> void:.*?label\.add_theme_font_size_override\("font_size", 18\)\n\t\titems_list_container\.add_child\(label\)',
    items_list_func,
    content,
    flags=re.DOTALL
)

# In _transition_to_game, game_data_items is populated.
# We can update the shop icon there.
# Let's add an onready var for the Potion IconRect
content = content.replace(
    "@onready var add_potion_button := $CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer2/AddPotionButton",
    "@onready var add_potion_button := $CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer2/AddPotionButton\n@onready var shop_potion_icon := $CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/IconRect\n@onready var shop_potion_name := $CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer/NameLabel\n@onready var shop_potion_desc := $CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer/DescLabel"
)

# And right after `game_data_items = game_data.get("items", {})` we set the shop potion icon and desc.
update_shop_potion_logic = '''		game_data_items = game_data.get("items", {})

		# Update shop potion UI dynamically
		var potion_data = game_data_items.get("101000100", {})
		if potion_data:
			shop_potion_name.text = potion_data.get("name", "Potion")
			var strings = potion_data.get("strings", {})
			var desc_short_list = strings.get("desc_short", [])
			if desc_short_list and desc_short_list.size() > 0:
				shop_potion_desc.text = desc_short_list[0]
			var icon_name = potion_data.get("icon", "")
			if icon_name != "":
				var tex = load("res://assets/items/" + icon_name)
				if tex:
					shop_potion_icon.texture = tex'''

content = content.replace('game_data_items = game_data.get("items", {})', update_shop_potion_logic)

with open('godot/demo.gd', 'w') as f:
    f.write(content)
