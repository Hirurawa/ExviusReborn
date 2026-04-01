import re

with open('godot/demo.tscn', 'r') as f:
    content = f.read()

# Add BottomNav to CanvasLayer
bottom_nav = """[node name="BottomNav" type="PanelContainer" parent="CanvasLayer"]
visible = false
anchors_preset = 12
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_top = -60.0
grow_horizontal = 2
grow_vertical = 0

[node name="HBox" type="HBoxContainer" parent="CanvasLayer/BottomNav"]
layout_mode = 2
alignment = 1
theme_override_constants/separation = 10

[node name="HomeButton" type="Button" parent="CanvasLayer/BottomNav/HBox"]
custom_minimum_size = Vector2(100, 50)
layout_mode = 2
text = "Home"

[node name="UnitsButton" type="Button" parent="CanvasLayer/BottomNav/HBox"]
custom_minimum_size = Vector2(100, 50)
layout_mode = 2
text = "Units"

[node name="ItemsButton" type="Button" parent="CanvasLayer/BottomNav/HBox"]
custom_minimum_size = Vector2(100, 50)
layout_mode = 2
text = "Items"

[node name="SummonButton" type="Button" parent="CanvasLayer/BottomNav/HBox"]
custom_minimum_size = Vector2(100, 50)
layout_mode = 2
text = "Summon"

[node name="FriendsButton" type="Button" parent="CanvasLayer/BottomNav/HBox"]
custom_minimum_size = Vector2(100, 50)
layout_mode = 2
text = "Friends"

"""

# Let's insert it before LoginUI instead to avoid the regex duplicate issue
content = content.replace('[node name="LoginUI" type="Control" parent="CanvasLayer" unique_id=1106424834]', bottom_nav + '[node name="LoginUI" type="Control" parent="CanvasLayer" unique_id=1106424834]')

# Remove the old buttons from GameUI
content = content.replace('''[node name="FriendsButton" type="Button" parent="CanvasLayer/GameUI" unique_id=853502796]
layout_mode = 1
anchors_preset = 3
anchor_left = 1.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -100.0
offset_top = -50.0
offset_right = -10.0
offset_bottom = -10.0
grow_horizontal = 0
grow_vertical = 0
text = "Friends"

''', '')

content = content.replace('''[node name="UnitsButton" type="Button" parent="CanvasLayer/GameUI" unique_id=791310302]
layout_mode = 1
anchors_preset = 2
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 10.0
offset_top = -50.0
offset_right = 100.0
offset_bottom = -10.0
grow_vertical = 0
text = "Units"

''', '')

content = content.replace('''[node name="ItemsButton" type="Button" parent="CanvasLayer/GameUI" unique_id=76072141]
layout_mode = 1
anchors_preset = 2
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 110.0
offset_top = -50.0
offset_right = 200.0
offset_bottom = -10.0
grow_vertical = 0
text = "Items"

''', '')

content = content.replace('''[node name="SummonButton" type="Button" parent="CanvasLayer/GameUI" unique_id=875945712]
layout_mode = 1
anchors_preset = 2
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 210.0
offset_top = -50.0
offset_right = 300.0
offset_bottom = -10.0
grow_vertical = 0
text = "Summon"

''', '')

# Remove BackHomeButtons
content = content.replace('''[node name="BackHomeButton" type="Button" parent="CanvasLayer/FriendsUI/VBoxContainer" unique_id=584398201]
layout_mode = 2
text = "Back Home"

''', '')

content = content.replace('''[node name="BackHomeButton" type="Button" parent="CanvasLayer/UnitsUI/VBoxContainer" unique_id=1303272049]
layout_mode = 2
text = "Back Home"

''', '')

content = content.replace('''[node name="BackHomeButton" type="Button" parent="CanvasLayer/ItemsUI/VBoxContainer" unique_id=563129181]
layout_mode = 2
text = "Back Home"

''', '')

content = content.replace('''[node name="BackHomeButton" type="Button" parent="CanvasLayer/SummonUI/VBoxContainer" unique_id=1592844208]
layout_mode = 2
text = "Back Home"

''', '')

with open('godot/demo.tscn', 'w') as f:
    f.write(content)
