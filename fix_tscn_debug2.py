# The issue is that ALL my 65 paths are broken because my regex replacement from earlier messed up the `.tscn` structure.
# Why? Because I changed UIs to offset_top=120.0
# The regex was:
# rf'(\[node name="{page}" type="Control" parent="CanvasLayer".*?\n'
# rf'(:?visible = false\n)?'
# rf'layout_mode = 3\n'
# rf'anchors_preset = 15\n'
# rf'anchor_right = 1\.0\n'
# rf'anchor_bottom = 1\.0\n)'
# And I replaced it with `offset_top = 120.0\n`.
# Wait, did that accidentally delete something or truncate the file or mess up the parent definitions?
# Let's inspect demo.tscn.
with open('godot/demo.tscn', 'r') as f:
    print("Length of demo.tscn:", len(f.read()))
