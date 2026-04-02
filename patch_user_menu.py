with open('godot/demo.gd', 'r') as f:
    content = f.read()
content = content.replace('$CanvasLayer/GameUI/UserMenuButton', '$CanvasLayer/UserMenuButton')
with open('godot/demo.gd', 'w') as f:
    f.write(content)

with open('godot/demo.tscn', 'r') as f:
    content = f.read()
content = content.replace('parent="CanvasLayer/GameUI" unique_id=360065264]\nlayout_mode = 0', 'parent="CanvasLayer" unique_id=360065264]\nlayout_mode = 0')
content = content.replace('parent="CanvasLayer/GameUI" unique_id=360065264]', 'parent="CanvasLayer" unique_id=360065264]')
with open('godot/demo.tscn', 'w') as f:
    f.write(content)
