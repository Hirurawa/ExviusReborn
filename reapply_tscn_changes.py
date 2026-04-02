import re

with open('godot/demo.tscn', 'r') as f:
    content = f.read()

# 1. Update NRG Layout
pattern_nrg = re.compile(
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

content, _ = pattern_nrg.subn(new_nrg_layout, content)


# 2. Make UIs have offset_top = 120.0
for page in ["GameUI", "FriendsUI", "UnitsUI", "UnitDetailUI", "ItemsUI", "ShopUI", "SummonUI"]:
    pattern_ui = re.compile(
        rf'(\[node name="{page}" type="Control" parent="CanvasLayer".*?\n'
        rf'(:?visible = false\n)?'
        rf'layout_mode = 3\n'
        rf'anchors_preset = 15\n'
        rf'anchor_right = 1\.0\n'
        rf'anchor_bottom = 1\.0\n)'
    )
    content = pattern_ui.sub(r'\1offset_top = 120.0\n', content)

# 3. Units UI offset_bottom
old_units_vbox = r'''\[node name="VBoxContainer" type="VBoxContainer" parent="CanvasLayer/UnitsUI".*?\nlayout_mode = 1\nanchors_preset = 8\nanchor_left = 0\.5\nanchor_top = 0\.5\nanchor_right = 0\.5\nanchor_bottom = 0\.5\noffset_left = -200\.0\noffset_top = -200\.0\noffset_right = 200\.0\noffset_bottom = 200\.0\ngrow_horizontal = 2\ngrow_vertical = 2'''
new_units_vbox = '''[node name="VBoxContainer" type="VBoxContainer" parent="CanvasLayer/UnitsUI"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_bottom = -60.0
grow_horizontal = 2
grow_vertical = 2'''
content = re.sub(old_units_vbox, new_units_vbox, content, flags=re.DOTALL)

# 4. Shop UI Layout
old_shop_ui = r'''\[node name="VBoxContainer" type="VBoxContainer" parent="CanvasLayer/ShopUI"\]
layout_mode = 1
anchors_preset = 8
anchor_left = 0\.5
anchor_top = 0\.5
anchor_right = 0\.5
anchor_bottom = 0\.5
offset_left = -200\.0
offset_top = -200\.0
offset_right = 200\.0
offset_bottom = 200\.0
grow_horizontal = 2
grow_vertical = 2

\[node name="TitleLabel" type="Label" parent="CanvasLayer/ShopUI/VBoxContainer"\]
layout_mode = 2
text = "Shop"
horizontal_alignment = 1

\[node name="ShopFeedbackLabel" type="Label" parent="CanvasLayer/ShopUI/VBoxContainer"\]
layout_mode = 2
horizontal_alignment = 1

\[node name="AddPotionButton" type="Button" parent="CanvasLayer/ShopUI/VBoxContainer"\]
layout_mode = 2
text = "Buy Potion \(100 Gil\)"'''

new_shop_ui = '''[node name="VBoxContainer" type="VBoxContainer" parent="CanvasLayer/ShopUI"]
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
text = "Buy"'''
content, _ = re.subn(old_shop_ui, new_shop_ui, content, flags=re.DOTALL)


# 5. Move TopHeader and its children out of GameUI into CanvasLayer
# Because Godot scene structure relies on hierarchy in text file, we must just replace "CanvasLayer/GameUI/TopHeader" with "CanvasLayer/TopHeader".
# AND we have to move the whole block of nodes starting with TopHeader and all its descendants to be outside GameUI.
# Wait, if we just replace `parent="CanvasLayer/GameUI/TopHeader"` with `parent="CanvasLayer/TopHeader"` Godot might complain if it's lexically inside the GameUI block, but it actually doesn't care!
# Godot scene parser only cares about the `parent=` path to attach it to the tree.
# The only issue is that `TopHeader` itself needs to be `parent="CanvasLayer"`.

# Replace `CanvasLayer/GameUI/TopHeader` with `CanvasLayer/TopHeader` everywhere
content = content.replace('CanvasLayer/GameUI/TopHeader', 'CanvasLayer/TopHeader')

# Move UserMenuButton to CanvasLayer
content = content.replace('parent="CanvasLayer/GameUI" unique_id=360065264]', 'parent="CanvasLayer" unique_id=360065264]')

# Update BottomNav so it renders at the bottom. The simplest way is to ensure UIs render before it, or set Z-index. Godot respects the order in the file.
# By replacing the paths, the node TopHeader is now attached to CanvasLayer.
# It is declared early in the file, so it will be drawn BEFORE other CanvasLayer children.
# This means TopHeader will be behind UnitsUI, etc., if they overlap.
# But since we set offset_top=120.0 on all UIs, they don't overlap! So drawing order doesn't even matter visually.

with open('godot/demo.tscn', 'w') as f:
    f.write(content)
