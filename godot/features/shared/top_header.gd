extends VBoxContainer

@onready var gil_label: Label = $TopRow/HBox/GilLabel
@onready var lapis_label: Label = $TopRow/HBox/LapisLabel
@onready var user_info_label: Label = $TopRow/HBox/UserInfoLabel

@onready var rank_label: Label = $BottomRow/HBox/RankContainer/RankLabel
@onready var xp_bar: ProgressBar = $BottomRow/HBox/EXPContainer/ProgressBar
@onready var xp_label: Label = $BottomRow/HBox/EXPContainer/ProgressBar/XPLabel

@onready var energy_bar: ProgressBar = $BottomRow/HBox/EnergyContainer/NRGTopHBox/ProgressBar
@onready var energy_label: Label = $BottomRow/HBox/EnergyContainer/NRGTopHBox/ProgressBar/EnergyText
@onready var energy_time_label: Label = $BottomRow/HBox/EnergyContainer/NRGTimeLabel

@onready var debug_xp_input: LineEdit = $DebugXPContainer/XPInput
@onready var debug_add_xp_button: Button = $DebugXPContainer/AddXPButton
@onready var debug_gil_input: LineEdit = $DebugWalletContainer/GilInput
@onready var debug_add_gil_button: Button = $DebugWalletContainer/AddGilButton
@onready var debug_lapis_input: LineEdit = $DebugWalletContainer/LapisInput
@onready var debug_add_lapis_button: Button = $DebugWalletContainer/AddLapisButton

func _ready() -> void:
	DataManager.rank_updated.connect(_on_rank_updated)
	DataManager.nrg_updated.connect(_on_nrg_updated)
	DataManager.currency_updated.connect(_on_currency_updated)
	DataManager.account_updated.connect(_on_account_updated)
	DataManager.data_loaded.connect(_on_data_loaded)

	debug_add_xp_button.pressed.connect(_on_debug_add_xp)
	debug_add_gil_button.pressed.connect(_on_debug_add_gil)
	debug_add_lapis_button.pressed.connect(_on_debug_add_lapis)

func _on_rank_updated(rank: int, xp: int, next_rank_xp: int) -> void:
	rank_label.text = str(rank)
	if next_rank_xp > 0:
		xp_bar.max_value = next_rank_xp
		xp_bar.value = xp
	xp_label.text = "%d / %d" % [xp, next_rank_xp]

func _on_nrg_updated(current_nrg: int, max_nrg: int, time_until_next: float) -> void:
	if max_nrg > 0:
		energy_bar.max_value = max_nrg
		energy_bar.value = min(current_nrg, max_nrg)
	energy_label.text = "%d/%d" % [current_nrg, max_nrg]

	if current_nrg >= max_nrg:
		energy_time_label.text = "Fully Charged"
	else:
		var minutes: int = int(time_until_next) / 60
		var seconds: int = int(time_until_next) % 60
		energy_time_label.text = "%02d:%02d" % [minutes, seconds]

func _on_currency_updated(gil: int, lapis: int) -> void:
	gil_label.text = "Gil: %d" % gil
	lapis_label.text = "Lapis: %d" % lapis

func _on_account_updated(username: String) -> void:
	if username != "":
		user_info_label.text = username

func _on_data_loaded() -> void:
	if DataManager.account_info and DataManager.account_info.user.username != "":
		user_info_label.text = DataManager.account_info.user.username
	else:
		user_info_label.text = "Player"

func _on_debug_add_xp() -> void:
	var xp: int = debug_xp_input.text.to_int()
	if xp > 0:
		debug_xp_input.text = ""
		DataManager.add_rank_xp(xp)

func _on_debug_add_gil() -> void:
	var gil: int = debug_gil_input.text.to_int()
	if gil > 0:
		debug_gil_input.text = ""
		DataManager.add_currency(gil, 0)

func _on_debug_add_lapis() -> void:
	var lapis: int = debug_lapis_input.text.to_int()
	if lapis > 0:
		debug_lapis_input.text = ""
		DataManager.add_currency(0, lapis)
