import re

with open('godot/demo.gd', 'r') as f:
    content = f.read()

# Replace current_energy / max_energy vars
content = content.replace("var current_energy: int = 0", "var current_nrg: int = 0")
content = content.replace("var max_energy: int = 0", "var max_nrg: int = 0\nvar nrg_regen_rate_seconds: int = 300\nvar seconds_until_next_nrg: float = 0.0")

# Find update stats ui and replace it
old_update_stats_ui = r'''func _update_stats_ui\(\) -> void:
	var required_xp = current_rank \* 100
	stats_rank_label\.text = "%d" % current_rank

	if required_xp > 0:
		stats_xp_bar\.max_value = required_xp
		stats_xp_bar\.value = current_xp

	stats_xp_label\.text = "%d / %d" % \[current_xp, required_xp\]

	if max_energy > 0:
		stats_energy_bar\.max_value = max_energy
		# Prevent bar from overflowing UI, though text will show overflow
		stats_energy_bar\.value = min\(current_energy, max_energy\)

	stats_energy_label\.text = "%d/%d" % \[current_energy, max_energy\]'''

new_update_stats_ui = '''func _update_stats_ui() -> void:
	var required_xp = current_rank * 100
	stats_rank_label.text = "%d" % current_rank

	if required_xp > 0:
		stats_xp_bar.max_value = required_xp
		stats_xp_bar.value = current_xp

	stats_xp_label.text = "%d / %d" % [current_xp, required_xp]

	if max_nrg > 0:
		stats_energy_bar.max_value = max_nrg
		# Prevent bar from overflowing UI, though text will show overflow
		stats_energy_bar.value = min(current_nrg, max_nrg)

	stats_energy_label.text = "%d/%d" % [current_nrg, max_nrg]'''

content = re.sub(old_update_stats_ui, new_update_stats_ui, content)

# _process function
process_func = '''func _process(delta: float) -> void:
	if not game_ui.visible and not bottom_nav.visible:
		return # Only process if the user is in a state where UI might be visible

	if max_nrg > 0 and current_nrg < max_nrg:
		seconds_until_next_nrg -= delta
		if seconds_until_next_nrg <= 0:
			current_nrg += 1
			seconds_until_next_nrg = nrg_regen_rate_seconds
			_update_stats_ui()

		var time_node = stats_energy_bar.get_node_or_null("NRGTimeLabel")
		if time_node:
			var minutes = int(seconds_until_next_nrg) / 60
			var seconds = int(seconds_until_next_nrg) % 60
			time_node.text = "%02d:%02d" % [minutes, seconds]
	else:
		var time_node = stats_energy_bar.get_node_or_null("NRGTimeLabel")
		if time_node:
			time_node.text = "Fully Charged"
'''

# Find the end of _ready
ready_end_pattern = re.compile(r'func _ready\(\) -> void:.*?func _update_stats_ui\(\) -> void:', re.DOTALL)
match = ready_end_pattern.search(content)

if match:
    # insert process before update_stats_ui
    content = content[:match.end() - len('func _update_stats_ui() -> void:')] + process_func + '\n' + 'func _update_stats_ui() -> void:' + content[match.end():]

# In _on_add_xp_button_pressed
old_add_xp_replace = r'''current_energy = int\(result\.get\("energy", current_energy\)\)
		max_energy = int\(result\.get\("max_energy", max_energy\)\)'''

new_add_xp_replace = '''current_nrg = int(result.get("current_nrg", current_nrg))
		max_nrg = int(result.get("max_nrg", max_nrg))
		nrg_regen_rate_seconds = int(result.get("nrg_regen_rate_seconds", nrg_regen_rate_seconds))
		seconds_until_next_nrg = float(result.get("seconds_until_next_nrg", seconds_until_next_nrg))'''

content = re.sub(old_add_xp_replace, new_add_xp_replace, content)

# In _transition_to_game
old_transition_replace = r'''current_energy = int\(stats\.get\("energy", 41\)\)
	max_energy = int\(stats\.get\("max_energy", 41\)\)'''

new_transition_replace = '''current_nrg = int(stats.get("current_nrg", 41))
	max_nrg = int(stats.get("max_nrg", 41))
	nrg_regen_rate_seconds = int(stats.get("nrg_regen_rate_seconds", 300))
	seconds_until_next_nrg = float(stats.get("seconds_until_next_nrg", 0.0))'''

content = re.sub(old_transition_replace, new_transition_replace, content)

with open('godot/demo.gd', 'w') as f:
    f.write(content)
