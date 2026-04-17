extends Control

@onready var info_text: RichTextLabel = %InfoText
@onready var close_button: Button = %CloseButton

func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)

func _on_close_pressed() -> void:
	hide()

func setup(unit_data: Dictionary) -> void:
	if unit_data.is_empty():
		info_text.text = "[color=red]Invalid Unit Data[/color]"
		return

	var text_content = ""

	# Header
	var unit_name = unit_data.get("name", "Unknown")
	var current_hp = unit_data.get("current_hp", 0)
	var current_mp = unit_data.get("current_mp", 0)

	var final_stats = unit_data.get("final_stats", {})
	var max_hp = final_stats.get("max_hp", 0)
	var max_mp = final_stats.get("max_mp", 0)

	text_content += "[b][u]%s[/u][/b]\n" % unit_name
	text_content += "HP: %d / %d\n" % [current_hp, max_hp]
	text_content += "MP: %d / %d\n\n" % [current_mp, max_mp]

	# Stats
	var stats = final_stats.get("stats", {})
	var atk = stats.get("ATK", 0)
	var def = stats.get("DEF", 0)
	var mag = stats.get("MAG", 0)
	var spr = stats.get("SPR", 0)

	text_content += "[b]Stats[/b]\n"
	text_content += "ATK: %d  |  DEF: %d\n" % [atk, def]
	text_content += "MAG: %d  |  SPR: %d\n\n" % [mag, spr]

	# Active Effects
	var active_effects = unit_data.get("active_effects", [])
	text_content += "[b]Active Effects[/b]\n"

	if active_effects.size() == 0:
		text_content += "None\n"
	else:
		for effect in active_effects:
			var duration = effect.get("duration", 0)
			var modifiers = effect.get("modifiers", {})

			var modifiers_str = ""
			var keys = modifiers.keys()
			if keys.size() > 0:
				for i in range(keys.size()):
					var key = keys[i]
					var value = modifiers[key]
					modifiers_str += "%s: %s" % [str(key), str(value)]
					if i < keys.size() - 1:
						modifiers_str += ", "
			else:
				# If there are no modifiers, maybe dump other metadata
				var meta_keys = effect.keys()
				for i in range(meta_keys.size()):
					var key = meta_keys[i]
					if key != "duration" and key != "modifiers":
						modifiers_str += "%s: %s" % [str(key), str(effect[key])]
						if i < meta_keys.size() - 1:
							modifiers_str += ", "

			text_content += "[%d Turns] - %s\n" % [duration, modifiers_str]

	info_text.text = text_content
