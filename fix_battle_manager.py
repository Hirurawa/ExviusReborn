with open('./godot/features/battle/logic/battle_manager.gd', 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    if "elif action == CombatAction.SKILL or action == CombatAction.ITEM:" in line:
        pass # Handle below

for i in range(len(new_lines)):
    if "elif action == CombatAction.SKILL or action == CombatAction.ITEM:" in new_lines[i]:
        # Need to make sure unit_acted is emitted, actually it is emitted right before the if action == CombatAction.DEFEND block
        pass
