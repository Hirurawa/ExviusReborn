import re

with open('godot/demo.tscn', 'r') as f:
    content = f.read()

# I want to move TopHeader out of GameUI and put it directly under CanvasLayer
# But wait, GameUI is the "Home" page right now.
# GameUI nodes:
# [node name="GameUI" type="Control" parent="CanvasLayer"]
# Inside GameUI:
# [node name="TopHeader" type="VBoxContainer" parent="CanvasLayer/GameUI" ...

# Let's reparent TopHeader to CanvasLayer.
content = content.replace('parent="CanvasLayer/GameUI"', 'parent="CanvasLayer"', 1)

# Now, we need to push all content down so it's not hidden behind TopHeader.
# Wait, CanvasLayer children are overlapping by default, unless they are inside a VBoxContainer or we set anchor offsets.
# If I look at the other pages:
# CanvasLayer/FriendsUI
# CanvasLayer/UnitsUI
# CanvasLayer/ItemsUI
# CanvasLayer/ShopUI
# CanvasLayer/SummonUI
# CanvasLayer/GameUI
# All of these are full screen (anchor_right=1, anchor_bottom=1).
# We can just change their offset_top to match the height of TopHeader.
# TopHeader has: offset_bottom = 120.0
# Let's modify all UI pages so they have offset_top = 120.0 (or whatever pushes them down properly).
# Also, TopHeader needs to be drawn *after* or *before* the other UIs so it handles input correctly and isn't blocked.
# Actually, the user asked to push the content down.
# Let's use a main VBoxContainer for the layout? No, it's easier to just add offset_top = 120.0 to all the main UI panels.
# Or better, just reparent TopHeader to the CanvasLayer and set its offset_top to 0.

# Let's see how TopHeader is currently styled in the tscn:
# [node name="TopHeader" type="VBoxContainer" parent="CanvasLayer/GameUI" unique_id=1024202790]
# layout_mode = 1
# anchors_preset = 10
# anchor_right = 1.0
# offset_bottom = 120.0
# grow_horizontal = 2

# We will change the anchors/offsets of GameUI, FriendsUI, UnitsUI, ItemsUI, ShopUI, SummonUI.
# GameUI is currently:
# [node name="GameUI" type="Control" parent="CanvasLayer" unique_id=XYZ]
# layout_mode = 3
# anchors_preset = 15
# anchor_right = 1.0
# anchor_bottom = 1.0
# grow_horizontal = 2
# grow_vertical = 2

# Let's add `offset_top = 120.0` right after `anchor_bottom = 1.0`.
for page in ["GameUI", "FriendsUI", "UnitsUI", "UnitDetailUI", "ItemsUI", "ShopUI", "SummonUI"]:
    # The regex looks for the node declaration, layout_mode, anchors_preset, anchor_right, anchor_bottom
    pattern = re.compile(
        rf'(\[node name="{page}" type="Control" parent="CanvasLayer".*?\n'
        rf'(:?visible = false\n)?'
        rf'layout_mode = 3\n'
        rf'anchors_preset = 15\n'
        rf'anchor_right = 1\.0\n'
        rf'anchor_bottom = 1\.0\n)'
    )
    # We want to insert offset_top = 120.0 and offset_bottom = -60.0 (for BottomNav) ?
    # Currently BottomNav has offset_top = -60.0 and anchor_top = 1.0
    # The bottom nav sits at the bottom.

    # Let's just add `offset_top = 120.0`
    # Also need to make sure we don't duplicate.
    content = pattern.sub(r'\1offset_top = 120.0\n', content)

with open('godot/demo.tscn', 'w') as f:
    f.write(content)
