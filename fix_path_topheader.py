import re

with open('godot/demo.gd', 'r') as f:
    content = f.read()

# The error is:
# Node not found: "CanvasLayer/TopHeader/TopRow/HBox/UserInfoLabel" (relative to "/root/Demo").
# Wait, let's look at demo.tscn.
# In `demo.tscn` we still have:
# `parent="CanvasLayer/GameUI/TopHeader/TopRow"` and `parent="CanvasLayer/GameUI/TopHeader/TopRow/HBox"`
# for the labels like GilLabel, UserInfoLabel, LapisLabel!
# Our previous regex replacement `content = content.replace('parent="CanvasLayer/GameUI/TopHeader', 'parent="CanvasLayer/TopHeader')`
# didn't work properly if it didn't catch the descendants. Let's see if it caught it.
# Ah, the `unique_id` nodes were preserved with `parent="CanvasLayer/GameUI/TopHeader/TopRow"`...
# Let's fix ALL occurrences of `CanvasLayer/GameUI/TopHeader` to `CanvasLayer/TopHeader` in demo.tscn!

content = content.replace('CanvasLayer/GameUI/TopHeader', 'CanvasLayer/TopHeader')

with open('godot/demo.tscn', 'r') as f:
    tscn_content = f.read()

tscn_content = tscn_content.replace('CanvasLayer/GameUI/TopHeader', 'CanvasLayer/TopHeader')

with open('godot/demo.tscn', 'w') as f:
    f.write(tscn_content)
