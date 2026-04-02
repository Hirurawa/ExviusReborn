import re

with open('godot/demo.gd', 'r') as f:
    content = f.read()

# Update the path to EnergyText and NRGTimeLabel
# stats_energy_bar is currently $CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer/ProgressBar
# It should be $CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer/NRGTopHBox/ProgressBar
# stats_energy_label should be $CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer/NRGTopHBox/ProgressBar/EnergyText (wait, no, it's just relative to bar or directly referenced)

content = content.replace(
    "@onready var stats_energy_bar := $CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer/ProgressBar",
    "@onready var stats_energy_bar := $CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer/NRGTopHBox/ProgressBar"
)

content = content.replace(
    "@onready var stats_energy_label := $CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer/ProgressBar/EnergyText",
    "@onready var stats_energy_label := $CanvasLayer/GameUI/TopHeader/BottomRow/HBox/EnergyContainer/NRGTopHBox/ProgressBar/EnergyText"
)

# And in _process, NRGTimeLabel is a sibling of NRGTopHBox, so we can access it via stats_energy_bar.get_parent().get_parent().get_node("NRGTimeLabel")
# Because:
# EnergyContainer
#   NRGTopHBox
#     ProgressBar
#   NRGTimeLabel

old_process = '''		var time_node = stats_energy_bar.get_node_or_null("NRGTimeLabel")
		if time_node:
			var minutes = int(seconds_until_next_nrg) / 60
			var seconds = int(seconds_until_next_nrg) % 60
			time_node.text = "%02d:%02d" % [minutes, seconds]
	else:
		var time_node = stats_energy_bar.get_node_or_null("NRGTimeLabel")
		if time_node:
			time_node.text = "Fully Charged"'''

new_process = '''		var time_node = stats_energy_bar.get_parent().get_parent().get_node_or_null("NRGTimeLabel")
		if time_node:
			var minutes = int(seconds_until_next_nrg) / 60
			var seconds = int(seconds_until_next_nrg) % 60
			time_node.text = "%02d:%02d" % [minutes, seconds]
	else:
		var time_node = stats_energy_bar.get_parent().get_parent().get_node_or_null("NRGTimeLabel")
		if time_node:
			time_node.text = "Fully Charged"'''

content = content.replace(old_process, new_process)

with open('godot/demo.gd', 'w') as f:
    f.write(content)
