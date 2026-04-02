import re

with open('godot/demo.gd', 'r') as f:
    content = f.read()

# Replace all paths pointing to $CanvasLayer/GameUI/TopHeader with $CanvasLayer/TopHeader
content = content.replace('$CanvasLayer/GameUI/TopHeader', '$CanvasLayer/TopHeader')

with open('godot/demo.gd', 'w') as f:
    f.write(content)
