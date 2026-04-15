extends PanelContainer

@onready var gil_label: Label = %GilLabel
@onready var lapis_label: Label = %LapisLabel
@onready var nrg_bar: ProgressBar = %NRGBar
@onready var nrg_text_overlay: Label = %NRGTextOverlay
@onready var nrg_status_label: Label = %NRGStatusLabel
@onready var player_name_label: Label = %PlayerNameLabel
@onready var rank_number_label: Label = %RankNumberLabel
@onready var exp_bar: ProgressBar = %EXPBar
@onready var exp_status_label: Label = %EXPStatusLabel

func update_status(data: Dictionary) -> void:
	if data.has("gil"):
		gil_label.text = str(data.gil)

	if data.has("lapis"):
		lapis_label.text = str(data.lapis)

	if data.has("nrg") and data.has("max_nrg"):
		nrg_bar.max_value = data.max_nrg
		nrg_bar.value = data.nrg
		nrg_text_overlay.text = str(data.nrg) + "/" + str(data.max_nrg)
		if data.nrg >= data.max_nrg:
			nrg_status_label.text = "Fully Charged"
		else:
			nrg_status_label.text = "Charging..."

	if data.has("name"):
		player_name_label.text = str(data.name)

	if data.has("rank"):
		rank_number_label.text = str(data.rank)

	if data.has("exp"):
		exp_bar.value = data.exp

	if data.has("max_exp"):
		exp_bar.max_value = data.max_exp

	if data.has("exp_to_next_rank"):
		exp_status_label.text = "Rank Up in " + str(data.exp_to_next_rank)
