import re

with open('godot/demo.tscn', 'r') as f:
    content = f.read()

# We need to build the shop UI exactly like the picture provided by the user.
# The layout: "add icons to the items... The attached picture contains the layout for the shop. place the 'desc_short' under the name and instead of 'Details' the button should say 'Buy'"
# I need to create a template in the tscn for a generic "Shop Item Container" or just rewrite ShopUI VBoxContainer so that it has the layout.
# Right now, it just has an "AddPotionButton".
# Layout:
# HBoxContainer (the row)
#   TextureRect (for the icon)
#   VBoxContainer (for text)
#     Label (Name)
#     Label (desc_short)
#   Button ("Buy")

# The image shows rows that look like a list.
# For now, there is only Potion. We can either do it dynamically in gdscript or just update the static nodes since only potion is there right now.
# User: "Shop Layout: Only the potion is purchasable for now."
# So I can just make the layout for the potion directly in the TSCN.
# Then load the potion icon and text in GDScript, or hardcode the text if I'm doing static. Actually better to set it dynamically in gdscript, or just create the static nodes and assign them in gdscript so it's data-driven.
# Let's set up the static UI structure first for the one item slot in ShopUI.

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

# Using regex to replace
content, count = re.subn(old_shop_ui, new_shop_ui, content, flags=re.DOTALL)
print(f"Replaced {count} instances of shop UI.")

with open('godot/demo.tscn', 'w') as f:
    f.write(content)
