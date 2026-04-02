# Verify demo.gd ShopListContainer path
import re

with open('godot/demo.gd', 'r') as f:
    content = f.read()

# Make sure all UI references match the fixed demo.tscn
# AddPotionButton path:
content = content.replace("@onready var add_potion_button := $CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer2/AddPotionButton", "@onready var add_potion_button := $CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer2/AddPotionButton")

with open('godot/demo.gd', 'w') as f:
    f.write(content)
