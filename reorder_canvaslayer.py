import re

with open('godot/demo.tscn', 'r') as f:
    lines = f.readlines()

# We'll just extract TopHeader and UserMenuButton nodes entirely, and append them just above BottomNav.
# Wait, this requires matching node structures accurately.
# An easier way:
# Find start index of GameUI
# Find start index of TopHeader
# Find end of UserMenuButton
# We can use python to parse the blocks.

nodes = []
current_node = []
for line in lines:
    if line.startswith('[node '):
        if current_node:
            nodes.append(current_node)
        current_node = [line]
    else:
        if current_node:
            current_node.append(line)
        else:
            nodes.append([line]) # File header
if current_node:
    nodes.append(current_node)

header = []
canvas_nodes = []

for node in nodes:
    if node[0].startswith('[node'):
        canvas_nodes.append(node)
    else:
        header.append(node)

# We want TopHeader and its children, and UserMenuButton and its children, to be moved to the end, right before BottomNav.
# Actually, TopHeader and UserMenuButton are now under CanvasLayer.
# BottomNav is under CanvasLayer.
# We just need to make sure UIs (FriendsUI, UnitsUI, etc.) come BEFORE TopHeader, UserMenuButton, and BottomNav.

# Let's identify the root path of each node.
def get_parent(node_lines):
    match = re.search(r'parent="([^"]+)"', node_lines[0])
    if match:
        return match.group(1)
    return ""

def get_name(node_lines):
    match = re.search(r'name="([^"]+)"', node_lines[0])
    if match:
        return match.group(1)
    return ""

# Groups:
# 1. Non-CanvasLayer nodes
# 2. CanvasLayer UIs
# 3. TopHeader + UserMenuButton + BottomNav

# Let's reassemble
# It's actually safer to just edit the UIs to have `offset_top = 120.0` and we already reparented TopHeader.
# If we test UIs, the last drawn wins.
# Currently BottomNav is at the end.
# TopHeader is currently line 158.
# UIs are after it. So UIs will draw ON TOP of TopHeader.
# We MUST move TopHeader and UserMenuButton to the end of the file.

# Let's collect all lines that belong to TopHeader and UserMenuButton.
# The node hierarchy: any node whose parent is "CanvasLayer/TopHeader" or starts with "CanvasLayer/TopHeader/"
# Same for UserMenuButton.

top_header_nodes = []
user_menu_nodes = []
other_nodes = []

for node in canvas_nodes:
    name = get_name(node)
    parent = get_parent(node)
    path = parent + "/" + name if parent else name

    if path == "CanvasLayer/TopHeader" or path.startswith("CanvasLayer/TopHeader/"):
        top_header_nodes.append(node)
    elif path == "CanvasLayer/UserMenuButton" or path.startswith("CanvasLayer/UserMenuButton/"):
        user_menu_nodes.append(node)
    else:
        other_nodes.append(node)

# Now, we reconstruct the file:
# header
# other_nodes (excluding BottomNav)
# top_header_nodes
# user_menu_nodes
# BottomNav nodes

bottom_nav_nodes = []
remaining_nodes = []

for node in other_nodes:
    name = get_name(node)
    parent = get_parent(node)
    path = parent + "/" + name if parent else name
    if path == "CanvasLayer/BottomNav" or path.startswith("CanvasLayer/BottomNav/"):
        bottom_nav_nodes.append(node)
    else:
        remaining_nodes.append(node)

with open('godot/demo.tscn', 'w') as f:
    for h in header:
        f.writelines(h)
    for n in remaining_nodes:
        f.writelines(n)
    for n in top_header_nodes:
        f.writelines(n)
    for n in user_menu_nodes:
        f.writelines(n)
    for n in bottom_nav_nodes:
        f.writelines(n)
