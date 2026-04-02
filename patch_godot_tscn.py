import re

with open('godot/demo.tscn', 'r') as f:
    content = f.read()

# Since we need to replace the HBoxContainer with a VBoxContainer, and its children with an HBoxContainer + Label
# Let's use a non-greedy regex to replace the exact nodes.
# I'll preserve unique_ids if they exist, but the prompt says: "When manually modifying Godot .tscn files, do not add unique_id attributes to node definitions, as it is invalid syntax in Godot 4."
# So I should remove `unique_id=...` completely across the entire file just to be safe, but only if that's a known issue. Actually, the easiest way is to just do a smart regex replace.

pattern = re.compile(
    r'\[node name="EnergyContainer" type="HBoxContainer" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox".*?\n'
    r'layout_mode = 2\n'
    r'size_flags_horizontal = 3\n'
    r'\n'
    r'\[node name="Label" type="Label" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer".*?\n'
    r'layout_mode = 2\n'
    r'theme_override_colors/font_color = Color\(0\.5, 0\.8, 1, 1\)\n'
    r'theme_override_colors/font_outline_color = Color\(0, 0, 0, 1\)\n'
    r'theme_override_constants/outline_size = 4\n'
    r'theme_override_font_sizes/font_size = 18\n'
    r'text = "NRG"\n'
    r'vertical_alignment = 1\n'
    r'\n'
    r'\[node name="ProgressBar" type="ProgressBar" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer".*?\n'
    r'layout_mode = 2\n'
    r'size_flags_horizontal = 3\n'
    r'size_flags_vertical = 4\n'
    r'theme_override_styles/background = SubResource\("StyleBoxFlat_bg"\)\n'
    r'theme_override_styles/fill = SubResource\("StyleBoxFlat_nrg"\)\n'
    r'value = 100\.0\n'
    r'show_percentage = false\n'
    r'\n'
    r'\[node name="EnergyText" type="Label" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer/ProgressBar".*?\n'
    r'layout_mode = 1\n'
    r'anchors_preset = 15\n'
    r'anchor_right = 1\.0\n'
    r'anchor_bottom = 1\.0\n'
    r'grow_horizontal = 2\n'
    r'grow_vertical = 2\n'
    r'theme_override_colors/font_outline_color = Color\(0, 0, 0, 1\)\n'
    r'theme_override_constants/outline_size = 4\n'
    r'theme_override_font_sizes/font_size = 18\n'
    r'text = "150/178"\n'
    r'horizontal_alignment = 1\n'
    r'vertical_alignment = 1',
    re.DOTALL
)

new_nrg_layout = '''[node name="EnergyContainer" type="VBoxContainer" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox"]
layout_mode = 2
size_flags_horizontal = 3
alignment = 1

[node name="NRGTopHBox" type="HBoxContainer" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer"]
layout_mode = 2
size_flags_vertical = 3

[node name="Label" type="Label" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer/NRGTopHBox"]
layout_mode = 2
theme_override_colors/font_color = Color(0.5, 0.8, 1, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 18
text = "NRG"
vertical_alignment = 1

[node name="ProgressBar" type="ProgressBar" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer/NRGTopHBox"]
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 4
theme_override_styles/background = SubResource("StyleBoxFlat_bg")
theme_override_styles/fill = SubResource("StyleBoxFlat_nrg")
value = 100.0
show_percentage = false

[node name="EnergyText" type="Label" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer/NRGTopHBox/ProgressBar"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 18
text = "0/0"
horizontal_alignment = 1
vertical_alignment = 1

[node name="NRGTimeLabel" type="Label" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer"]
layout_mode = 2
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 3
theme_override_font_sizes/font_size = 14
text = "Fully Charged"
horizontal_alignment = 1
vertical_alignment = 1'''

new_content, count = pattern.subn(new_nrg_layout, content)
print(f"Replaced {count} instances.")

with open('godot/demo.tscn', 'w') as f:
    f.write(new_content)
