with open('./godot/features/battle/ui/combat_unit_panel.gd', 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)

with open('./godot/features/battle/ui/combat_unit_panel.gd', 'w') as f:
    f.writelines(new_lines)
