# Ah, I see! `[node name="TopRow" type="PanelContainer" parent="CanvasLayer/TopHeader"...` is directly below `GameUI` in `demo.tscn` but `TopHeader` itself was moved to the very bottom of the file!
# That means when parsing, `CanvasLayer/TopHeader` doesn't exist yet when it tries to add `TopRow` to it!
# Wait, Godot's scene format requires parent nodes to be declared BEFORE child nodes.
# When I moved TopHeader to the bottom of the file, I only moved `[node name="TopHeader" type="VBoxContainer" parent="CanvasLayer"...]` but I didn't move all its children!
# Let's fix this!

with open('godot/demo.tscn', 'r') as f:
    lines = f.readlines()

# Instead of moving nodes around in text, let's restore demo.tscn from git or just fix the order.
