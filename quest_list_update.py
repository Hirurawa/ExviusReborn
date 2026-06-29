import re

with open("godot/features/quest/quest_list_dialog.gd", "r") as f:
    content = f.read()

# We need to add town_id parameter and handle signals for map_ui.gd refresh
# Wait, actually we can just emit a signal from QuestListDialog or do things inline
