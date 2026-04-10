extends Node

signal data_loaded
signal login_success
signal login_failed(error_code: int)
signal register_success
signal register_failed(error_code: int)
signal account_updated(username: String)
signal rank_updated(rank: int, xp: int, next_rank_xp: int)
signal nrg_updated(current_nrg: int, max_nrg: int, time_until_next: float)
signal currency_updated(gil: int, lapis: int)
signal units_updated(units: Array)
signal items_updated(items: Array)
signal friends_updated(friends: Object)
signal friend_action_result(success: bool, message: String)
signal parties_updated(parties: Array)
signal party_save_requested(new_parties: Array)

var server_connection: Node

var current_rank: int = 1
var current_xp: int = 0
var next_rank_xp: int = 100
var current_nrg: int = 0
var max_nrg: int = 0
var nrg_regen_rate_seconds: int = 300
var seconds_until_next_nrg: float = 0.0

var gil: int = 0
var lapis: int = 0

var owned_units_ids: Array = []
var owned_items: Array = []
var parties: Array = []

var game_data_units: Dictionary = {}
var game_data_items: Dictionary = {}
var game_data_equipment: Dictionary = {}
var game_data_worlds: Dictionary = {}
var game_data_dungeons: Dictionary = {}
var game_data_missions: Dictionary = {}
var game_data_skills_magic: Dictionary = {}
var game_data_skills_ability: Dictionary = {}
var game_data_limitbursts: Dictionary = {}
var game_data_materia: Dictionary = {}
var game_data_equipment_icons: Dictionary = {}
var game_data_monsters = []

var account_info: Object = null

func _ready():
	var server_script = load("res://core/server_connection.gd")
	server_connection = server_script.new()
	server_connection.name = "ServerConnection"
	add_child(server_connection)

	party_save_requested.connect(save_parties)

func _process(delta: float) -> void:
	if max_nrg > 0 and current_nrg < max_nrg:
		seconds_until_next_nrg -= delta
		if seconds_until_next_nrg <= 0:
			current_nrg += 1
			seconds_until_next_nrg = nrg_regen_rate_seconds
			nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)
		else:
			# Still ticking, UI might want to know for the timer
			nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)

func authenticate(email: String, password: String):
	var result = await server_connection.authenticate_async(email, password)
	if result == OK:
		await _load_initial_data(email)
		login_success.emit()
	else:
		login_failed.emit(result)

func register(email: String, password: String, username: String):
	var result = await server_connection.register_async(email, password, username)
	if result == OK:
		await _load_initial_data(email)
		register_success.emit()
	else:
		register_failed.emit(result)

func logout():
	server_connection.logout()
	account_info = null

func update_account(new_username: String):
	var result = await server_connection.update_account_async(new_username)
	if result == OK:
		account_info = await server_connection.get_account_async()
		account_updated.emit(account_info.user.username)
		return true
	return false

func _load_initial_data(email: String):
	var stats = await server_connection.read_player_stats_async()
	current_rank = int(stats.get("rank", 1))
	current_xp = int(stats.get("xp", 0))
	next_rank_xp = int(stats.get("next_rank_xp", 100))
	current_nrg = int(stats.get("current_nrg", 41))
	max_nrg = int(stats.get("max_nrg", 41))
	nrg_regen_rate_seconds = int(stats.get("nrg_regen_rate_seconds", 300))
	seconds_until_next_nrg = float(stats.get("seconds_until_next_nrg", 0.0))
	rank_updated.emit(current_rank, current_xp, next_rank_xp)
	nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)

	owned_units_ids = await server_connection.read_player_units_async()
	units_updated.emit(owned_units_ids)

	owned_items = await server_connection.read_player_items_async()
	items_updated.emit(owned_items)

	parties = await server_connection.get_parties_async()
	parties_updated.emit(parties)

	if not AssetPatcher.patch_complete.is_connected(_on_patch_complete):
		AssetPatcher.patch_progress.connect(func(file_name, status):
			pass
		)
		AssetPatcher.patch_complete.connect(_on_patch_complete)

	AssetPatcher.server_connection = server_connection
	AssetPatcher.start_patching()
	await AssetPatcher.patch_complete

	account_info = await server_connection.get_account_async()
	if account_info:
		var wallet_str = account_info.wallet
		if wallet_str and wallet_str != "":
			var wallet = JSON.parse_string(wallet_str)
			if wallet and wallet is Dictionary:
				_update_wallet_data(wallet)

	data_loaded.emit()

func _on_patch_complete():
	game_data_units = AssetPatcher.get_data("units")
	game_data_items = AssetPatcher.get_data("items")
	game_data_equipment = AssetPatcher.get_data("equipment")
	game_data_worlds = AssetPatcher.get_data("worlds")
	game_data_dungeons = AssetPatcher.get_data("dungeons")
	game_data_skills_magic = AssetPatcher.get_data("skills_magic")
	game_data_skills_ability = AssetPatcher.get_data("skills_ability")
	game_data_limitbursts = AssetPatcher.get_data("limitbursts")
	game_data_materia = AssetPatcher.get_data("materia")
	game_data_equipment_icons = AssetPatcher.get_data("equipment-icons")
	game_data_monsters = AssetPatcher.get_data("monsters")

func _update_wallet_data(wallet: Dictionary):
	gil = int(wallet.get("gil", 0))
	lapis = int(wallet.get("lapis", 0))
	currency_updated.emit(gil, lapis)

func add_rank_xp(xp_to_add: int):
	var result = await server_connection.add_rank_xp_async(xp_to_add)
	if not result.is_empty():
		current_rank = int(result.get("rank", current_rank))
		current_xp = int(result.get("xp", current_xp))
		next_rank_xp = int(result.get("next_rank_xp", next_rank_xp))
		current_nrg = int(result.get("current_nrg", current_nrg))
		max_nrg = int(result.get("max_nrg", max_nrg))
		nrg_regen_rate_seconds = int(result.get("nrg_regen_rate_seconds", nrg_regen_rate_seconds))
		seconds_until_next_nrg = float(result.get("seconds_until_next_nrg", seconds_until_next_nrg))
		rank_updated.emit(current_rank, current_xp, next_rank_xp)
		nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)

func add_currency(gil_to_add: int, lapis_to_add: int):
	var result = await server_connection.add_currency_async(gil_to_add, lapis_to_add)
	if result.has("wallet"):
		var wallet = JSON.parse_string(result.wallet) if result.wallet is String else result.wallet
		_update_wallet_data(wallet)

func buy_item(item_id: String, quantity: int) -> Dictionary:
	var result = await server_connection.buy_item_async(item_id, quantity)
	if not result.has("error"):
		if result.has("items"):
			owned_items = result.items
			items_updated.emit(owned_items)
		if result.has("wallet"):
			var wallet = JSON.parse_string(result.wallet) if result.wallet is String else result.wallet
			_update_wallet_data(wallet)
	return result

func save_parties(new_parties: Array) -> Dictionary:
	var result = await server_connection.save_parties_async(new_parties)
	if not result.has("error"):
		parties = new_parties
		parties_updated.emit(parties)
	return result

func summon_units(amount: int) -> Array:
	var summoned_units = await server_connection.summon_units_async(amount)
	owned_units_ids.append_array(summoned_units)
	units_updated.emit(owned_units_ids)
	return summoned_units

func add_unit_xp(instance_id: String, xp_amount: int) -> Dictionary:
	var result = await server_connection.add_unit_xp_async(instance_id, xp_amount)
	if not result.has("error"):
		owned_units_ids = await server_connection.read_player_units_async()
		units_updated.emit(owned_units_ids)
	return result

func awaken_unit(instance_id: String) -> Dictionary:
	var result = await server_connection.awaken_unit_async(instance_id)
	if not result.has("error"):
		owned_units_ids = await server_connection.read_player_units_async()
		units_updated.emit(owned_units_ids)
	return result

func equip_item(instance_id: String, slot_id: String, item_id: String) -> Dictionary:
	var result = await server_connection.equip_item_async(instance_id, slot_id, item_id)
	if not result.has("error"):
		owned_units_ids = await server_connection.read_player_units_async()
		units_updated.emit(owned_units_ids)
	return result

func list_friends():
	var friends_list = await server_connection.list_friends_async()
	friends_updated.emit(friends_list)
	return friends_list

func add_friend(username: String):
	var result = await server_connection.add_friends_async(username)
	if result == OK:
		friend_action_result.emit(true, "Success")
		list_friends()
	else:
		friend_action_result.emit(false, "Error code: %d" % result)

func delete_friend(username: String):
	var result = await server_connection.delete_friends_async(username)
	if result == OK:
		friend_action_result.emit(true, "Success")
		list_friends()
	else:
		friend_action_result.emit(false, "Error code: %d" % result)

func perform_mission(mission_id: String) -> Dictionary:
	var result = await server_connection.perform_mission_async(mission_id)
	if not result.has("error"):
		if result.has("stats"):
			var stats = result.stats
			current_rank = int(stats.get("rank", current_rank))
			current_xp = int(stats.get("xp", current_xp))
			next_rank_xp = int(stats.get("next_rank_xp", next_rank_xp))
			current_nrg = int(stats.get("current_nrg", current_nrg))
			max_nrg = int(stats.get("max_nrg", max_nrg))
			nrg_regen_rate_seconds = int(stats.get("nrg_regen_rate_seconds", nrg_regen_rate_seconds))
			seconds_until_next_nrg = float(stats.get("seconds_until_next_nrg", seconds_until_next_nrg))
			rank_updated.emit(current_rank, current_xp, next_rank_xp)
			nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)
		if result.has("wallet"):
			var wallet = JSON.parse_string(result.wallet) if result.wallet is String else result.wallet
			_update_wallet_data(wallet)
	return result
