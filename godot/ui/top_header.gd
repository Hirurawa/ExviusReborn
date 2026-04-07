extends VBoxContainer

@onready var gil_label = $TopRow/HBox/GilLabel
@onready var lapis_label = $TopRow/HBox/LapisLabel
@onready var user_info_label = $TopRow/HBox/UserInfoLabel

@onready var rank_label = $BottomRow/HBox/RankContainer/RankLabel
@onready var xp_bar = $BottomRow/HBox/EXPContainer/ProgressBar
@onready var xp_label = $BottomRow/HBox/EXPContainer/ProgressBar/XPLabel

@onready var energy_bar = $BottomRow/HBox/EnergyContainer/NRGTopHBox/ProgressBar
@onready var energy_label = $BottomRow/HBox/EnergyContainer/NRGTopHBox/ProgressBar/EnergyText
@onready var energy_time_label = $BottomRow/HBox/EnergyContainer/NRGTimeLabel

@onready var debug_xp_input = $DebugXPContainer/XPInput
@onready var debug_add_xp_button = $DebugXPContainer/AddXPButton
@onready var debug_gil_input = $DebugWalletContainer/GilInput
@onready var debug_add_gil_button = $DebugWalletContainer/AddGilButton
@onready var debug_lapis_input = $DebugWalletContainer/LapisInput
@onready var debug_add_lapis_button = $DebugWalletContainer/AddLapisButton

func _ready():
	DataManager.rank_updated.connect(_on_rank_updated)
	DataManager.nrg_updated.connect(_on_nrg_updated)
	DataManager.currency_updated.connect(_on_currency_updated)
	DataManager.account_updated.connect(_on_account_updated)
	DataManager.data_loaded.connect(_on_data_loaded)

	debug_add_xp_button.pressed.connect(_on_debug_add_xp)
	debug_add_gil_button.pressed.connect(_on_debug_add_gil)
	debug_add_lapis_button.pressed.connect(_on_debug_add_lapis)

func _on_rank_updated(rank: int, xp: int, next_rank_xp: int):
	rank_label.text = str(rank)
	if next_rank_xp > 0:
		xp_bar.max_value = next_rank_xp
		xp_bar.value = xp
	xp_label.text = "%d / %d" % [xp, next_rank_xp]

func _on_nrg_updated(current_nrg: int, max_nrg: int, time_until_next: float):
	if max_nrg > 0:
		energy_bar.max_value = max_nrg
		energy_bar.value = min(current_nrg, max_nrg)
	energy_label.text = "%d/%d" % [current_nrg, max_nrg]

	if current_nrg >= max_nrg:
		energy_time_label.text = "Fully Charged"
	else:
		var minutes = int(time_until_next) / 60
		var seconds = int(time_until_next) % 60
		energy_time_label.text = "%02d:%02d" % [minutes, seconds]

func _on_currency_updated(gil: int, lapis: int):
	gil_label.text = "Gil: %d" % gil
	lapis_label.text = "Lapis: %d" % lapis

func _on_account_updated(username: String):
	if username != "":
		user_info_label.text = username

func _on_data_loaded():
	if DataManager.account_info and DataManager.account_info.user.username != "":
		user_info_label.text = DataManager.account_info.user.username
	else:
		user_info_label.text = "Player"

func _on_debug_add_xp():
	var xp = debug_xp_input.text.to_int()
	if xp > 0:
		debug_xp_input.text = ""
		DataManager.add_rank_xp(xp)

func _on_debug_add_gil():
	var gil = debug_gil_input.text.to_int()
	if gil > 0:
		debug_gil_input.text = ""
		DataManager.add_currency(gil, 0)

func _on_debug_add_lapis():
	var lapis = debug_lapis_input.text.to_int()
	if lapis > 0:
		debug_lapis_input.text = ""
		DataManager.add_currency(0, lapis)
