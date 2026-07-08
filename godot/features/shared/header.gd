extends Node

@onready var gil_label: Label = $header_coin_num
@onready var lapis_label: Label = $header_dia_num
@onready var user_info_label: Label = $header_user_name

@onready var rank_label: Label = $header_lv_num
@onready var xp_bar: TextureProgressBar = $header_exp_bar
@onready var xp_label: Label = $header_exp_num

@onready var energy_bar: TextureProgressBar = $header_stamina_bar
@onready var energy_label_current: Label = $header_stamina_num_now
@onready var energy_label_max: Label = $header_stamina_num
@onready var energy_time_label: Label = $header_stamina_time

func _ready() -> void:
	PlayerProfile.rank_updated.connect(_on_rank_updated)
	PlayerProfile.nrg_updated.connect(_on_nrg_updated)
	PlayerProfile.currency_updated.connect(_on_currency_updated)
	AccountService.account_updated.connect(_on_account_updated)
	AccountService.data_loaded.connect(_on_data_loaded)


func _on_rank_updated(rank: int, xp: int, next_rank_xp: int) -> void:
	rank_label.text = str(rank)
	if next_rank_xp > 0:
		xp_bar.max_value = next_rank_xp
		xp_bar.value = xp
	xp_label.text = "%d" % int(next_rank_xp - xp)

func _on_nrg_updated(current_nrg: int, max_nrg: int, time_until_next: float) -> void:
	if max_nrg > 0:
		energy_bar.max_value = max_nrg
		energy_bar.value = min(current_nrg, max_nrg)
	energy_label_current.text = "%d" % current_nrg
	energy_label_max.text = "%d" % max_nrg

	if current_nrg >= max_nrg:
		energy_time_label.text = "Fully Charged"
	else:
		@warning_ignore("integer_division")
		var minutes: int = int(time_until_next) / 60
		var seconds: int = int(time_until_next) % 60
		energy_time_label.text = "%02d:%02d" % [minutes, seconds]

func _on_currency_updated(gil: int, lapis: int) -> void:
	gil_label.text = "%d" % gil
	lapis_label.text = "%d" % lapis

func _on_account_updated(username: String) -> void:
	if username != "":
		user_info_label.text = username

func _on_data_loaded() -> void:
	if AccountService.current_username != "":
		user_info_label.text = AccountService.current_username
	elif user_info_label.text == "":
		user_info_label.text = "Player"
