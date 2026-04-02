# Let's also make sure demo.gd doesn't have any leftover `GameUI/TopHeader`
import re

with open('godot/demo.gd', 'r') as f:
    content = f.read()

content = content.replace('CanvasLayer/GameUI/TopHeader', 'CanvasLayer/TopHeader')

with open('godot/demo.gd', 'w') as f:
    f.write(content)
