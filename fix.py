with open('godot/features/shared/TopHeader.tscn', 'r') as f:
    content = f.read()

content = content.replace('''[node name="RankNumberLabel" type="Label" parent="MainSplit/CenterColumn"]
unique_name_in_owner = true
layout_mode = 2
theme_override_font_sizes/font_size = 24
text = "1"
horizontal_alignment = 1''', '''[node name="RankNumberLabel" type="Label" parent="MainSplit/CenterColumn"]
unique_name_in_owner = true
layout_mode = 2
theme_override_font_sizes/font_size = 24
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_constants/outline_size = 2
text = "1"
horizontal_alignment = 1''')

with open('godot/features/shared/TopHeader.tscn', 'w') as f:
    f.write(content)
