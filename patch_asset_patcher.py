import sys

def modify_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Fix JSON parsing checks
    content = content.replace("if parsed:", "if parsed != null:")

    with open(filepath, 'w') as f:
        f.write(content)

modify_file('godot/core/asset_patcher.gd')
