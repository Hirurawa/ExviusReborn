#!/bin/bash
for file in godot/ui/*.gd godot/autoloads/*.gd godot/*.gd; do
    if [ -f "$file" ]; then
        godot --headless --check-only -s "$file" 2>/dev/null
    fi
done
