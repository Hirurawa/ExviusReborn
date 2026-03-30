extends Panel

@onready var log_label = $RichTextLabel

func write_message(text: String):
	# Adds a new line with the message and auto-scrolls
	log_label.append_text(text + "\n")
