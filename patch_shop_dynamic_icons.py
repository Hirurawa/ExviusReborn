import re

with open('godot/demo.gd', 'r') as f:
    content = f.read()

# Add a function to set the potion icon statically since we only have one item in the shop.
# Wait, user asked: "add icons to the items... the file is indicated in the items json with the 'icon' key"
# The UI for Items page also displays items. Let's check Items page.
