import re

with open('godot/demo.gd', 'r') as f:
    content = f.read()

content = content.replace("@onready var add_potion_button := $CanvasLayer/ShopUI/VBoxContainer/AddPotionButton", "@onready var add_potion_button := $CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer2/AddPotionButton")

# Now let's dynamically load the Potion's image and info from items.json if needed, or we can just statically assign the image.
# We have IconRect: $CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/IconRect
# And we can just load the texture when the shop opens, or in _ready.
# Actually, the user asked to "add icons to the items... the file is indicated in the items json with the 'icon' key. the assets are located in the assets/items folder in godot."
# We should probably dynamically parse the items.json in GDScript and set the icons in the shop and items list.

with open('godot/demo.gd', 'w') as f:
    f.write(content)
