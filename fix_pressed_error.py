# The other error is: Invalid access to property or key 'pressed' on a base object of type 'null instance'.
# Let's find all `.pressed` in demo.gd to see which one might be null.

with open('godot/demo.gd', 'r') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if '.pressed.connect' in line:
        print(f"Line {i+1}: {line.strip()}")
