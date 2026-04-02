# Wow, the file size dropped from 39k to 23k! I deleted half the file with my regex `re.sub(..., flags=re.DOTALL)`!
# Oh no, DOTALL makes `.*?` match across newlines in unpredictable ways if there are multiple matches or if it matches until the LAST instance of something.
# Specifically, in my `reapply_tscn_changes.py`, I did:
# old_shop_ui = r'\[node name="VBoxContainer" type="VBoxContainer" parent="CanvasLayer/ShopUI"\].*?text = "Buy Potion \(100 Gil\)"'
# Since DOTALL was active, it probably swallowed everything between `[node name="VBoxContainer" type="VBoxContainer" parent="CanvasLayer/ShopUI"]` and the end of the file or another text.

# Let's restore the original demo.tscn from HEAD
git checkout HEAD -- godot/demo.tscn
