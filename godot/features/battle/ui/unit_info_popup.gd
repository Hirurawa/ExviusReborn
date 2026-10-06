class_name UnitInfoPopup
extends Control

## The long-press info window: a combatant's name, HP, MP, live stats (with buffs and
## breaks) and its statuses with the turns they have left.

@onready var info_text: RichTextLabel = %InfoText
@onready var close_button: Button = %CloseButton

## Id of the combatant shown, so the battle screen can refresh it; -1 when none.
var shown_id: int = -1


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)


func _on_close_pressed() -> void:
	shown_id = -1
	hide()


func setup_from_combatant(fighter: Combatant) -> void:
	if fighter == null:
		shown_id = -1
		info_text.text = "[color=red]Invalid Unit Data[/color]"
		return
	shown_id = fighter.id
	var lines: PackedStringArray = [
		"[b][u]%s[/u][/b]" % fighter.name,
		"HP: %d / %d" % [fighter.hp, fighter.max_hp],
		"MP: %d / %d" % [fighter.mp, fighter.max_mp],
		"",
		"[b]Stats[/b]",
		"ATK: %d  |  DEF: %d" % [fighter.stat("ATK"), fighter.stat("DEF")],
		"MAG: %d  |  SPR: %d" % [fighter.stat("MAG"), fighter.stat("SPR")],
		"",
		"[b]Active Effects[/b]",
	]
	if fighter.statuses.is_empty():
		lines.append("None")
	for status in fighter.statuses:
		lines.append(status.describe())
	info_text.text = "\n".join(lines)
