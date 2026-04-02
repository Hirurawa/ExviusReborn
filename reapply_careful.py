import re

with open('godot/demo.tscn', 'r') as f:
    content = f.read()

# Let's do replacements without DOTALL, or with very explicit boundaries.

# 1. NRG Layout
# We want to replace the `EnergyContainer` HBox and its children with a `VBoxContainer` containing `NRGTopHBox` and `NRGTimeLabel`.
# I will just find the exact block and replace it using normal string replacement.
old_nrg = """[node name="EnergyContainer" type="HBoxContainer" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox" unique_id=990643421]
layout_mode = 2
size_flags_horizontal = 3

[node name="Label" type="Label" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer" unique_id=1683328830]
layout_mode = 2
theme_override_colors/font_color = Color(0.5, 0.8, 1, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 18
text = "NRG"
vertical_alignment = 1

[node name="ProgressBar" type="ProgressBar" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer" unique_id=23248404]
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 4
theme_override_styles/background = SubResource("StyleBoxFlat_bg")
theme_override_styles/fill = SubResource("StyleBoxFlat_nrg")
value = 100.0
show_percentage = false

[node name="EnergyText" type="Label" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer/ProgressBar" unique_id=1935224873]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 18
text = "150/178"
horizontal_alignment = 1
vertical_alignment = 1"""

new_nrg = """[node name="EnergyContainer" type="VBoxContainer" parent="CanvasLayer/GameUI/TopHeader/BottomRow/HBox"]
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
vertical_alignment = 1"""

content = content.replace(old_nrg, new_nrg)

# 2. Offset Top = 120
# I will just insert `offset_top = 120.0` inside each of the UI Control nodes.
for page in ["GameUI", "FriendsUI", "UnitsUI", "UnitDetailUI", "ItemsUI", "ShopUI", "SummonUI"]:
    # Find the node block
    pattern = re.compile(
        rf'(\[node name="{page}" type="Control" parent="CanvasLayer".*?\]\n'
        rf'(?:visible = false\n)?'
        rf'layout_mode = 3\n'
        rf'anchors_preset = 15\n'
        rf'anchor_right = 1\.0\n'
        rf'anchor_bottom = 1\.0\n)'
    )
    content = pattern.sub(r'\g<1>offset_top = 120.0\n', content)

# 3. Units VBox
old_units_vbox = """[node name="VBoxContainer" type="VBoxContainer" parent="CanvasLayer/UnitsUI" unique_id=1428925648]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -200.0
offset_top = -200.0
offset_right = 200.0
offset_bottom = 200.0
grow_horizontal = 2
grow_vertical = 2"""
new_units_vbox = """[node name="VBoxContainer" type="VBoxContainer" parent="CanvasLayer/UnitsUI"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_bottom = -60.0
grow_horizontal = 2
grow_vertical = 2"""
content = content.replace(old_units_vbox, new_units_vbox)

# 4. Shop UI
# Shop UI doesn't have unique_ids for the inner nodes, except maybe VBoxContainer? Let's check original.
