import re

with open('godot/demo.tscn', 'r') as f:
    content = f.read()

# We need to stretch the window containing the units to touch the sides of the screen.
# The units should span from the bottom edge of the top part to the top edge of the bottom bar.
# In other words, full screen UIs should have anchors_preset = 15, anchor_right = 1.0, anchor_bottom = 1.0.
# Currently they do, but their child VBoxContainer has anchors_preset = 8 (center) and fixed size offset_left=-200...
# We need to change that child VBoxContainer to anchors_preset=15 (full rect).
# Let's see:

old_vbox = r'''\[node name="VBoxContainer" type="VBoxContainer" parent="CanvasLayer/UnitsUI".*?\nlayout_mode = 1\nanchors_preset = 8\nanchor_left = 0\.5\nanchor_top = 0\.5\nanchor_right = 0\.5\nanchor_bottom = 0\.5\noffset_left = -200\.0\noffset_top = -200\.0\noffset_right = 200\.0\noffset_bottom = 200\.0\ngrow_horizontal = 2\ngrow_vertical = 2'''

new_vbox = '''[node name="VBoxContainer" type="VBoxContainer" parent="CanvasLayer/UnitsUI"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_bottom = -60.0
grow_horizontal = 2
grow_vertical = 2'''
# wait, bottom_nav offset_top is -60.0. If we do offset_bottom = -60.0 on the VBoxContainer, it will perfectly avoid overlapping with the bottom nav.
# Actually, the user says "The units should span from the bottom edge of the top part to the top edge of the bottom bar, and the left and right edge of the window".
# UnitsUI already has offset_top = 120.0, so the top edge is correct.
# To not overlap with BottomNav, it should either have `offset_bottom = -60.0` or its parent `UnitsUI` should have `offset_bottom = -60.0`.
# Currently UnitsUI has `anchor_bottom = 1.0` but no `offset_bottom`.
# Let's just set the VBoxContainer's `offset_bottom = -60.0`.

content = re.sub(old_vbox, new_vbox, content, flags=re.DOTALL)

with open('godot/demo.tscn', 'w') as f:
    f.write(content)
