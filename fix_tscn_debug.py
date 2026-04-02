# Let's see what is on demo.gd:116
with open('godot/demo.gd', 'r') as f:
    lines = f.readlines()
print("Line 116:", lines[115].strip())

# And check what happened to ItemsListContainer in demo.tscn
