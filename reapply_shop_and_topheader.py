import re

with open('godot/demo.tscn', 'r') as f:
    content = f.read()

old_shop = """[node name="VBoxContainer" type="VBoxContainer" parent="CanvasLayer/ShopUI"]
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
grow_vertical = 2

[node name="TitleLabel" type="Label" parent="CanvasLayer/ShopUI/VBoxContainer"]
layout_mode = 2
text = "Shop"
horizontal_alignment = 1

[node name="ShopFeedbackLabel" type="Label" parent="CanvasLayer/ShopUI/VBoxContainer"]
layout_mode = 2
horizontal_alignment = 1

[node name="AddPotionButton" type="Button" parent="CanvasLayer/ShopUI/VBoxContainer"]
layout_mode = 2
text = "Buy Potion (100 Gil)"
"""

new_shop = """[node name="VBoxContainer" type="VBoxContainer" parent="CanvasLayer/ShopUI"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
theme_override_constants/separation = 10

[node name="TitleLabel" type="Label" parent="CanvasLayer/ShopUI/VBoxContainer"]
layout_mode = 2
theme_override_font_sizes/font_size = 24
text = "Shop"
horizontal_alignment = 1

[node name="ShopFeedbackLabel" type="Label" parent="CanvasLayer/ShopUI/VBoxContainer"]
layout_mode = 2
horizontal_alignment = 1
theme_override_colors/font_color = Color(0.8, 0.8, 0.2, 1)

[node name="ScrollContainer" type="ScrollContainer" parent="CanvasLayer/ShopUI/VBoxContainer"]
layout_mode = 2
size_flags_vertical = 3

[node name="ShopListContainer" type="VBoxContainer" parent="CanvasLayer/ShopUI/VBoxContainer/ScrollContainer"]
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 3
theme_override_constants/separation = 10

[node name="PotionItem" type="PanelContainer" parent="CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer"]
layout_mode = 2
theme_override_styles/panel = SubResource("StyleBoxFlat_2")

[node name="HBoxContainer" type="HBoxContainer" parent="CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem"]
layout_mode = 2
theme_override_constants/separation = 15

[node name="IconRect" type="TextureRect" parent="CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer"]
custom_minimum_size = Vector2(64, 64)
layout_mode = 2
expand_mode = 1
stretch_mode = 5

[node name="VBoxContainer" type="VBoxContainer" parent="CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer"]
layout_mode = 2
size_flags_horizontal = 3
alignment = 1

[node name="NameLabel" type="Label" parent="CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer"]
layout_mode = 2
theme_override_font_sizes/font_size = 18
text = "Potion"

[node name="DescLabel" type="Label" parent="CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer"]
layout_mode = 2
theme_override_colors/font_color = Color(0.7, 0.7, 0.7, 1)
theme_override_font_sizes/font_size = 14
text = "Restore a small amount of HP to one ally"
autowrap_mode = 2

[node name="VBoxContainer2" type="VBoxContainer" parent="CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer"]
layout_mode = 2
alignment = 1

[node name="PriceLabel" type="Label" parent="CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer2"]
layout_mode = 2
text = "100 Gil"
horizontal_alignment = 1

[node name="AddPotionButton" type="Button" parent="CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer2"]
custom_minimum_size = Vector2(80, 40)
layout_mode = 2
text = "Buy"
"""

content = content.replace(old_shop, new_shop)

# Reparenting TopHeader and UserMenu
# First we find the node lines for them
# [node name="TopHeader" type="VBoxContainer" parent="CanvasLayer/GameUI" unique_id=1024202790]
content = content.replace('parent="CanvasLayer/GameUI/TopHeader', 'parent="CanvasLayer/TopHeader')
content = content.replace('[node name="TopHeader" type="VBoxContainer" parent="CanvasLayer/GameUI"', '[node name="TopHeader" type="VBoxContainer" parent="CanvasLayer"')
content = content.replace('[node name="UserMenuButton" type="MenuButton" parent="CanvasLayer/GameUI"', '[node name="UserMenuButton" type="MenuButton" parent="CanvasLayer"')

# Also let's run the other changes
old_nrg = """[node name="EnergyContainer" type="HBoxContainer" parent="CanvasLayer/TopHeader/BottomRow/HBox" unique_id=990643421]
layout_mode = 2
size_flags_horizontal = 3

[node name="Label" type="Label" parent="CanvasLayer/TopHeader/BottomRow/HBox/EnergyContainer" unique_id=1683328830]
layout_mode = 2
theme_override_colors/font_color = Color(0.5, 0.8, 1, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 18
text = "NRG"
vertical_alignment = 1

[node name="ProgressBar" type="ProgressBar" parent="CanvasLayer/TopHeader/BottomRow/HBox/EnergyContainer" unique_id=23248404]
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 4
theme_override_styles/background = SubResource("StyleBoxFlat_bg")
theme_override_styles/fill = SubResource("StyleBoxFlat_nrg")
value = 100.0
show_percentage = false

[node name="EnergyText" type="Label" parent="CanvasLayer/TopHeader/BottomRow/HBox/EnergyContainer/ProgressBar" unique_id=1935224873]
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

new_nrg = """[node name="EnergyContainer" type="VBoxContainer" parent="CanvasLayer/TopHeader/BottomRow/HBox"]
layout_mode = 2
size_flags_horizontal = 3
alignment = 1

[node name="NRGTopHBox" type="HBoxContainer" parent="CanvasLayer/TopHeader/BottomRow/HBox/EnergyContainer"]
layout_mode = 2
size_flags_vertical = 3

[node name="Label" type="Label" parent="CanvasLayer/TopHeader/BottomRow/HBox/EnergyContainer/NRGTopHBox"]
layout_mode = 2
theme_override_colors/font_color = Color(0.5, 0.8, 1, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 18
text = "NRG"
vertical_alignment = 1

[node name="ProgressBar" type="ProgressBar" parent="CanvasLayer/TopHeader/BottomRow/HBox/EnergyContainer/NRGTopHBox"]
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 4
theme_override_styles/background = SubResource("StyleBoxFlat_bg")
theme_override_styles/fill = SubResource("StyleBoxFlat_nrg")
value = 100.0
show_percentage = false

[node name="EnergyText" type="Label" parent="CanvasLayer/TopHeader/BottomRow/HBox/EnergyContainer/NRGTopHBox/ProgressBar"]
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

[node name="NRGTimeLabel" type="Label" parent="CanvasLayer/TopHeader/BottomRow/HBox/EnergyContainer"]
layout_mode = 2
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 3
theme_override_font_sizes/font_size = 14
text = "Fully Charged"
horizontal_alignment = 1
vertical_alignment = 1"""
content = content.replace(old_nrg, new_nrg)

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

with open('godot/demo.tscn', 'w') as f:
    f.write(content)
