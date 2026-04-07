import sys
# Just thinking: set_root calls queue_free on everything in the stack, clears the array, and then calls push().
# Wait, if set_root calls queue_free on everything in the stack, but the array is cleared, `if not _menu_stack.is_empty():` is false in `push()`.
# So it pushes the new menu successfully.
