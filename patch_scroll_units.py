import re

with open('godot/demo.tscn', 'r') as f:
    content = f.read()

# We need to ensure that the units span correctly from top to bottom edge, and left/right.
# UnitsUI already has offset_top=120.0
# The VBoxContainer inside has anchor_right=1.0 and anchor_bottom=1.0 and offset_bottom=-60.0
# We need to make sure the ScrollContainer and the GridContainer are expanding to fill it.
# Check what ScrollContainer and GridContainer have:
# [node name="ScrollContainer" type="ScrollContainer" parent="CanvasLayer/UnitsUI/VBoxContainer"]
# layout_mode = 2
# size_flags_vertical = 3
# [node name="UnitsListContainer" type="GridContainer" parent="CanvasLayer/UnitsUI/VBoxContainer/ScrollContainer" unique_id=798742642]
# layout_mode = 2
# size_flags_horizontal = 3
# size_flags_vertical = 3
# columns = 5

# Let's verify this in the tscn.
