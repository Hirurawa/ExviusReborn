import re

with open('godot/demo.tscn', 'r') as f:
    content = f.read()

# I need to change all occurrences of `parent="CanvasLayer/GameUI/TopHeader...` to `parent="CanvasLayer/TopHeader...`
content = content.replace('parent="CanvasLayer/GameUI/TopHeader', 'parent="CanvasLayer/TopHeader')

# And there's also user_menu_button which was in GameUI.
# Wait, user_menu_button isn't inside TopHeader?
# Let's check user_menu_button
