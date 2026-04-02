import re
with open('godot/demo.gd', 'r') as f:
    content = f.read()

content = content.replace("func _ready() -> void:", "func _ready() -> void:\n\ttop_header.hide()\n\tuser_menu_button.hide()")

with open('godot/demo.gd', 'w') as f:
    f.write(content)
