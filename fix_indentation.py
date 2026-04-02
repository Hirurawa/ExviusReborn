import re

with open('godot/demo.gd', 'r') as f:
    content = f.read()

# Fix the over-indented line:
# `\t\t\t\tgame_data_items = game_data.get("items", {})` -> `\t\tgame_data_items = game_data.get("items", {})`

content = content.replace(
    '\t\t\t\tgame_data_items = game_data.get("items", {})',
    '\t\tgame_data_items = game_data.get("items", {})'
)
# Just in case it's actually 3 tabs or something, let's use regex to enforce exactly 2 tabs since it's inside `if game_data:` inside `_transition_to_game`

content = re.sub(
    r'\n(\t+)game_data_items = game_data\.get\("items", \{\}\)\n',
    r'\n\t\tgame_data_items = game_data.get("items", {})\n',
    content
)

with open('godot/demo.gd', 'w') as f:
    f.write(content)
