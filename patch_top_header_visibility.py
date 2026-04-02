import re
with open('godot/demo.gd', 'r') as f:
    content = f.read()

# in _hide_all_ui, do we hide top_header? No, _hide_all_ui is used to swap tabs!
# BUT when logging out, we call _hide_all_ui and then we want to hide top_header.
# Let's add top_header.hide() and user_menu_button.hide() in _on_logout_pressed
content = content.replace("func _on_logout_pressed() -> void:\n\tserver_connection.logout()\n\t_hide_all_ui()\n\tbottom_nav.hide()", "func _on_logout_pressed() -> void:\n\tserver_connection.logout()\n\t_hide_all_ui()\n\tbottom_nav.hide()\n\ttop_header.hide()\n\tuser_menu_button.hide()")

# Also in _ready, make sure they are hidden at startup.
# _ready currently sets up things and eventually waits. Actually, wait... the nodes are visible by default.
# Let's add top_header.hide() to the start of _ready.
content = content.replace("func _ready() -> void:\n\tgame_ui.hide()", "func _ready() -> void:\n\tgame_ui.hide()\n\ttop_header.hide()\n\tuser_menu_button.hide()")

# Double check if _ready actually has game_ui.hide()
