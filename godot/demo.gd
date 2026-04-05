extends Node2D


@onready var server_connection := $ServerConnection

@onready var login_ui := $CanvasLayer/LoginUI
@onready var register_ui := $CanvasLayer/RegisterUI
@onready var game_ui := $CanvasLayer/GameUI

@onready var login_email_input := $CanvasLayer/LoginUI/VBoxContainer/EmailInput
@onready var login_password_input := $CanvasLayer/LoginUI/VBoxContainer/PasswordInput
@onready var login_feedback_label := $CanvasLayer/LoginUI/VBoxContainer/FeedbackLabel

@onready var register_username_input := $CanvasLayer/RegisterUI/VBoxContainer/UsernameInput
@onready var register_email_input := $CanvasLayer/RegisterUI/VBoxContainer/EmailInput
@onready var register_password_input := $CanvasLayer/RegisterUI/VBoxContainer/PasswordInput
@onready var register_feedback_label := $CanvasLayer/RegisterUI/VBoxContainer/FeedbackLabel

@onready var login_button := $CanvasLayer/LoginUI/VBoxContainer/HBoxContainer/LoginButton
@onready var go_to_register_button := $CanvasLayer/LoginUI/VBoxContainer/HBoxContainer/GoToRegisterButton

@onready var register_button := $CanvasLayer/RegisterUI/VBoxContainer/HBoxContainer/RegisterButton
@onready var back_to_login_button := $CanvasLayer/RegisterUI/VBoxContainer/HBoxContainer/BackToLoginButton

@onready var edit_profile_ui := $CanvasLayer/EditProfileUI
@onready var edit_new_username_input := $CanvasLayer/EditProfileUI/VBoxContainer/NewUsernameInput
@onready var edit_feedback_label := $CanvasLayer/EditProfileUI/VBoxContainer/FeedbackLabel
@onready var edit_update_button := $CanvasLayer/EditProfileUI/VBoxContainer/HBoxContainer/UpdateButton
@onready var edit_cancel_button := $CanvasLayer/EditProfileUI/VBoxContainer/HBoxContainer/CancelButton


@onready var stats_rank_label := $CanvasLayer/TopHeader/BottomRow/HBox/RankContainer/RankLabel
@onready var stats_xp_label := $CanvasLayer/TopHeader/BottomRow/HBox/EXPContainer/ProgressBar/XPLabel
@onready var stats_xp_bar := $CanvasLayer/TopHeader/BottomRow/HBox/EXPContainer/ProgressBar
@onready var stats_xp_input := $CanvasLayer/TopHeader/DebugXPContainer/XPInput
@onready var stats_add_xp_button := $CanvasLayer/TopHeader/DebugXPContainer/AddXPButton
@onready var stats_energy_bar := $CanvasLayer/TopHeader/BottomRow/HBox/EnergyContainer/NRGTopHBox/ProgressBar
@onready var stats_energy_label := $CanvasLayer/TopHeader/BottomRow/HBox/EnergyContainer/NRGTopHBox/ProgressBar/EnergyText

@onready var stats_gil_label := $CanvasLayer/TopHeader/TopRow/HBox/GilLabel
@onready var stats_lapis_label := $CanvasLayer/TopHeader/TopRow/HBox/LapisLabel
@onready var debug_gil_input := $CanvasLayer/TopHeader/DebugWalletContainer/GilInput
@onready var debug_add_gil_button := $CanvasLayer/TopHeader/DebugWalletContainer/AddGilButton
@onready var debug_lapis_input := $CanvasLayer/TopHeader/DebugWalletContainer/LapisInput
@onready var debug_add_lapis_button := $CanvasLayer/TopHeader/DebugWalletContainer/AddLapisButton

var current_rank: int = 1
var current_xp: int = 0
var next_rank_xp: int = 100
var current_nrg: int = 0
var max_nrg: int = 0
var nrg_regen_rate_seconds: int = 300
var seconds_until_next_nrg: float = 0.0
@onready var user_info_label := $CanvasLayer/TopHeader/TopRow/HBox/UserInfoLabel
@onready var user_menu_button := $CanvasLayer/UserMenuButton

@onready var top_header := $CanvasLayer/TopHeader
@onready var bottom_nav := $CanvasLayer/BottomNav
@onready var home_button := $CanvasLayer/BottomNav/HBox/HomeButton
@onready var friends_button := $CanvasLayer/BottomNav/HBox/FriendsButton
@onready var units_button := $CanvasLayer/BottomNav/HBox/UnitsButton
@onready var items_button := $CanvasLayer/BottomNav/HBox/ItemsButton
@onready var summon_button := $CanvasLayer/BottomNav/HBox/SummonButton
@onready var shop_button := $CanvasLayer/BottomNav/HBox/ShopButton
@onready var world_map_button := $CanvasLayer/WorldMapButton

@onready var shop_ui := $CanvasLayer/ShopUI
@onready var shop_feedback_label := $CanvasLayer/ShopUI/VBoxContainer/ShopFeedbackLabel

@onready var map_ui := $CanvasLayer/MapUI
@onready var map_world_option := $CanvasLayer/MapUI/VBoxContainer/HBoxContainer/WorldOptionButton
@onready var map_region_option := $CanvasLayer/MapUI/VBoxContainer/HBoxContainer/RegionOptionButton
@onready var map_subregion_option := $CanvasLayer/MapUI/VBoxContainer/HBoxContainer/SubregionOptionButton
@onready var map_scroll := $CanvasLayer/MapUI/VBoxContainer/MapScrollContainer
@onready var map_back_button := $CanvasLayer/MapUI/VBoxContainer/TopBar/BackButton
@onready var map_sizer := $CanvasLayer/MapUI/VBoxContainer/MapScrollContainer/MapSizer
@onready var map_content := $CanvasLayer/MapUI/VBoxContainer/MapScrollContainer/MapSizer/MapContent
@onready var map_image := $CanvasLayer/MapUI/VBoxContainer/MapScrollContainer/MapSizer/MapContent/MapImage
@onready var mission_details_popup := $CanvasLayer/MapUI/MissionDetailsPopup
@onready var mission_dungeon_name := $CanvasLayer/MapUI/MissionDetailsPopup/VBoxContainer/DungeonNameLabel
@onready var missions_list_container := $CanvasLayer/MapUI/MissionDetailsPopup/VBoxContainer/ScrollContainer/MissionsListContainer

@onready var units_ui := $CanvasLayer/UnitsUI
@onready var units_list_container := $CanvasLayer/UnitsUI/VBoxContainer/ScrollContainer/UnitsListContainer

@onready var unit_detail_ui := $CanvasLayer/UnitDetailUI
@onready var unit_detail_sprite := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/SpritePlaceholder
@onready var unit_detail_back_button := $CanvasLayer/UnitDetailUI/VBoxContainer/TopBar/BackButton
@onready var unit_detail_name_label := $CanvasLayer/UnitDetailUI/VBoxContainer/TopBar/TitleBox/NameLabel
@onready var unit_detail_rarity_label := $CanvasLayer/UnitDetailUI/VBoxContainer/TopBar/TitleBox/InfoHBox/RarityLabel
@onready var unit_detail_level_label := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/LevelHBox/LevelLabel
@onready var unit_detail_next_xp_label := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/LevelHBox/NextXPLabel
@onready var unit_detail_hp_value := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/HPValue
@onready var unit_detail_mp_value := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/MPValue
@onready var unit_detail_atk_value := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/ATKValue
@onready var unit_detail_def_value := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/DEFValue
@onready var unit_detail_mag_value := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/MAGValue
@onready var unit_detail_spr_value := $CanvasLayer/UnitDetailUI/VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/SPRValue
@onready var unit_detail_add_xp_button := $CanvasLayer/UnitDetailUI/VBoxContainer/ActionsHBox/AddXPButton
@onready var unit_detail_awaken_button := $CanvasLayer/UnitDetailUI/VBoxContainer/ActionsHBox/AwakenButton

@onready var items_ui := $CanvasLayer/ItemsUI
@onready var items_list_container := $CanvasLayer/ItemsUI/VBoxContainer/ScrollContainer/ItemsListContainer
@onready var add_potion_button := $CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer2/AddPotionButton
@onready var shop_potion_icon := $CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/IconRect
@onready var shop_potion_name := $CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer/NameLabel
@onready var shop_potion_desc := $CanvasLayer/ShopUI/VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer/DescLabel

var game_data_units: Dictionary = {}
var game_data_items: Dictionary = {}
var game_data_weapons: Dictionary = {}
var game_data_worlds: Dictionary = {}
var game_data_dungeons: Dictionary = {}
var game_data_missions: Dictionary = {}

var current_selected_world: String = ""
var current_selected_region: String = ""
var current_selected_subregion: String = ""


var map_zoom_level: float = 1.0
var _is_panning_map: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO

var owned_units_ids: Array = []
var owned_items: Array = []

@onready var friends_ui := $CanvasLayer/FriendsUI
@onready var add_friend_input := $CanvasLayer/FriendsUI/VBoxContainer/AddFriendHBox/AddFriendInput
@onready var add_friend_button := $CanvasLayer/FriendsUI/VBoxContainer/AddFriendHBox/AddFriendButton
@onready var friends_feedback_label := $CanvasLayer/FriendsUI/VBoxContainer/FeedbackLabel
@onready var friends_list_container := $CanvasLayer/FriendsUI/VBoxContainer/ScrollContainer/FriendsListContainer

@onready var summon_ui := $CanvasLayer/SummonUI
@onready var summon_perform_button := $CanvasLayer/SummonUI/VBoxContainer/PerformSummonButton
@onready var summon_overlay := $CanvasLayer/SummonUI/SummonOverlay
@onready var summon_results_list := $CanvasLayer/SummonUI/SummonOverlay/VBoxContainer/ScrollContainer/ResultsListContainer
@onready var summon_close_overlay_button := $CanvasLayer/SummonUI/SummonOverlay/VBoxContainer/CloseOverlayButton

func _ready() -> void:
	top_header.hide()
	user_menu_button.hide()
	world_map_button.hide()

	stats_add_xp_button.pressed.connect(_on_add_xp_button_pressed)
	debug_add_gil_button.pressed.connect(_on_add_gil_button_pressed)
	debug_add_lapis_button.pressed.connect(_on_add_lapis_button_pressed)

	login_button.pressed.connect(_on_login_button_pressed)
	go_to_register_button.pressed.connect(_on_go_to_register_button_pressed)
	register_button.pressed.connect(_on_register_button_pressed)
	back_to_login_button.pressed.connect(_on_back_to_login_button_pressed)

	edit_update_button.pressed.connect(_on_edit_update_button_pressed)
	edit_cancel_button.pressed.connect(_on_edit_cancel_button_pressed)

	user_menu_button.get_popup().id_pressed.connect(_on_user_menu_id_pressed)

	home_button.pressed.connect(_on_home_button_pressed)
	friends_button.pressed.connect(_on_friends_button_pressed)
	add_friend_button.pressed.connect(_on_add_friend_button_pressed)

	units_button.pressed.connect(_on_units_button_pressed)

	items_button.pressed.connect(_on_items_button_pressed)
	add_potion_button.pressed.connect(_on_add_potion_button_pressed)

	summon_button.pressed.connect(_on_summon_button_pressed)
	shop_button.pressed.connect(_on_shop_button_pressed)

	summon_perform_button.pressed.connect(_on_summon_perform_button_pressed)
	summon_close_overlay_button.pressed.connect(_on_summon_close_overlay_button_pressed)

	unit_detail_back_button.pressed.connect(_on_unit_detail_back_button_pressed)
	
	world_map_button.pressed.connect(_on_world_map_button_pressed)
	map_back_button.pressed.connect(_on_map_back_button_pressed)
	map_world_option.item_selected.connect(_on_map_world_selected)
	map_region_option.item_selected.connect(_on_map_region_selected)
	map_subregion_option.item_selected.connect(_on_map_subregion_selected)
	
	map_scroll.gui_input.connect(_on_map_scroll_gui_input)

func _process(delta: float) -> void:
	if not game_ui.visible and not bottom_nav.visible:
		return # Only process if the user is in a state where UI might be visible

	if max_nrg > 0 and current_nrg < max_nrg:
		seconds_until_next_nrg -= delta
		if seconds_until_next_nrg <= 0:
			current_nrg += 1
			seconds_until_next_nrg = nrg_regen_rate_seconds
			_update_stats_ui()

		var time_node = stats_energy_bar.get_parent().get_parent().get_node_or_null("NRGTimeLabel")
		if time_node:
			var minutes = int(seconds_until_next_nrg) / 60
			var seconds = int(seconds_until_next_nrg) % 60
			time_node.text = "%02d:%02d" % [minutes, seconds]
	else:
		var time_node = stats_energy_bar.get_parent().get_parent().get_node_or_null("NRGTimeLabel")
		if time_node:
			time_node.text = "Fully Charged"

func _update_stats_ui() -> void:
	var required_xp = next_rank_xp
	stats_rank_label.text = "%d" % current_rank

	if required_xp > 0:
		stats_xp_bar.max_value = required_xp
		stats_xp_bar.value = current_xp

	stats_xp_label.text = "%d / %d" % [current_xp, required_xp]

	if max_nrg > 0:
		stats_energy_bar.max_value = max_nrg
		# Prevent bar from overflowing UI, though text will show overflow
		stats_energy_bar.value = min(current_nrg, max_nrg)

	stats_energy_label.text = "%d/%d" % [current_nrg, max_nrg]

func _on_add_xp_button_pressed() -> void:
	var xp_to_add: int = stats_xp_input.text.to_int()
	if xp_to_add <= 0:
		return

	stats_xp_input.text = ""

	var result = await server_connection.add_rank_xp_async(xp_to_add)
	if not result.is_empty():
		current_rank = int(result.get("rank", current_rank))
		current_xp = int(result.get("xp", current_xp))
		next_rank_xp = int(result.get("next_rank_xp", next_rank_xp))
		current_nrg = int(result.get("current_nrg", current_nrg))
		max_nrg = int(result.get("max_nrg", max_nrg))
		nrg_regen_rate_seconds = int(result.get("nrg_regen_rate_seconds", nrg_regen_rate_seconds))
		seconds_until_next_nrg = float(result.get("seconds_until_next_nrg", seconds_until_next_nrg))
		_update_stats_ui()

func _on_user_menu_id_pressed(id: int) -> void:
	if id == 0:
		_on_edit_profile_pressed()
	elif id == 1:
		_on_logout_pressed()

func _update_wallet_ui(wallet: Dictionary) -> void:
	var gil: int = int(wallet.get("gil", 0))
	var lapis: int = int(wallet.get("lapis", 0))
	stats_gil_label.text = "Gil: %d" % gil
	stats_lapis_label.text = "Lapis: %d" % lapis

func _on_add_gil_button_pressed() -> void:
	var gil_to_add: int = debug_gil_input.text.to_int()
	if gil_to_add <= 0:
		return

	debug_gil_input.text = ""
	var result = await server_connection.add_currency_async(gil_to_add, 0)
	if result.has("wallet"):
		var wallet = JSON.parse_string(result.wallet) if result.wallet is String else result.wallet
		_update_wallet_ui(wallet)

func _on_add_lapis_button_pressed() -> void:
	var lapis_to_add: int = debug_lapis_input.text.to_int()
	if lapis_to_add <= 0:
		return

	debug_lapis_input.text = ""
	var result = await server_connection.add_currency_async(0, lapis_to_add)
	if result.has("wallet"):
		var wallet = JSON.parse_string(result.wallet) if result.wallet is String else result.wallet
		_update_wallet_ui(wallet)

func _hide_all_ui() -> void:
	game_ui.hide()
	friends_ui.hide()
	units_ui.hide()
	items_ui.hide()
	summon_ui.hide()
	shop_ui.hide()
	edit_profile_ui.hide()
	unit_detail_ui.hide()
	map_ui.hide()
	world_map_button.hide()

func _on_shop_button_pressed() -> void:
	_hide_all_ui()
	shop_ui.show()
	shop_feedback_label.text = ""

func _on_home_button_pressed() -> void:
	_hide_all_ui()
	game_ui.show()
	bottom_nav.show()
	world_map_button.show()

func _on_edit_profile_pressed() -> void:
	_hide_all_ui()
	bottom_nav.hide()
	edit_profile_ui.show()
	edit_new_username_input.text = ""
	edit_feedback_label.text = "Enter new username"

func _on_edit_cancel_button_pressed() -> void:
	edit_profile_ui.hide()
	game_ui.show()
	bottom_nav.show()
	world_map_button.show()

func _on_friends_button_pressed() -> void:
	_hide_all_ui()
	friends_ui.show()
	friends_feedback_label.text = ""
	add_friend_input.text = ""
	_refresh_friends_list()

func _on_units_button_pressed() -> void:
	_hide_all_ui()
	units_ui.show()
	_refresh_units_list()

func _on_items_button_pressed() -> void:
	_hide_all_ui()
	items_ui.show()
	_refresh_items_list()

func _on_world_map_button_pressed() -> void:
	_hide_all_ui()
	bottom_nav.hide()
	map_ui.show()
	top_header.show()
	_populate_world_options()
	map_zoom_level = 1.0
	map_content.scale = Vector2(map_zoom_level, map_zoom_level)
	map_sizer.custom_minimum_size = Vector2(2000, 2000) * map_zoom_level

func _on_map_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_panning_map = true
				_last_mouse_pos = event.global_position
			else:
				_is_panning_map = false
		elif event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var old_zoom = map_zoom_level
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				map_zoom_level = clamp(map_zoom_level + 0.1, 0.5, 3.0)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				map_zoom_level = clamp(map_zoom_level - 0.1, 0.5, 3.0)
			
			if old_zoom != map_zoom_level:
				map_content.scale = Vector2(map_zoom_level, map_zoom_level)
				map_sizer.custom_minimum_size = Vector2(2000, 2000) * map_zoom_level
			# Accept the event to stop ScrollContainer from scrolling up/down with wheel
			map_scroll.accept_event()

	elif event is InputEventMouseMotion and _is_panning_map:
		map_scroll.scroll_horizontal -= int(event.relative.x)
		map_scroll.scroll_vertical -= int(event.relative.y)

func _on_map_back_button_pressed() -> void:
	_hide_all_ui()
	game_ui.show()
	bottom_nav.show()
	world_map_button.show()

func _populate_world_options() -> void:
	map_world_option.clear()
	map_region_option.clear()
	map_subregion_option.clear()
	
	for child in map_content.get_children():
		if child != map_image:
			map_content.remove_child(child)
			child.queue_free()

	map_world_option.add_item("Select a World", 0)
	map_world_option.set_item_metadata(0, "")
	
	var idx = 1
	for world_id in game_data_worlds.keys():
		var world_data = game_data_worlds[world_id]
		var world_name = "Unknown World"
		if world_data.has("names") and world_data.names.size() > 0 and world_data.names[0]:
			world_name = world_data.names[0]
		map_world_option.add_item(world_name, idx)
		map_world_option.set_item_metadata(idx, world_id)
		idx += 1

func _on_map_world_selected(index: int) -> void:
	map_region_option.clear()
	map_subregion_option.clear()
	current_selected_world = map_world_option.get_item_metadata(index)
	
	for child in map_content.get_children():
		if child != map_image:
			map_content.remove_child(child)
			child.queue_free()

	if current_selected_world == "":
		return

	var world_data = game_data_worlds.get(current_selected_world, {})
	var regions = world_data.get("regions", {})

	map_region_option.add_item("Select a Region", 0)
	map_region_option.set_item_metadata(0, "")
	
	var idx = 1
	for region_id in regions.keys():
		var region_data = regions[region_id]
		var region_name = "Unknown Region"
		if region_data.has("names") and region_data.names.size() > 0 and region_data.names[0]:
			region_name = region_data.names[0]
		map_region_option.add_item(region_name, idx)
		map_region_option.set_item_metadata(idx, region_id)
		idx += 1

func _on_map_region_selected(index: int) -> void:
	map_subregion_option.clear()
	current_selected_region = map_region_option.get_item_metadata(index)
	
	for child in map_content.get_children():
		if child != map_image:
			map_content.remove_child(child)
			child.queue_free()

	if current_selected_region == "" or current_selected_world == "":
		return

	var world_data = game_data_worlds.get(current_selected_world, {})
	var regions = world_data.get("regions", {})
	var region_data = regions.get(current_selected_region, {})
	var subregions = region_data.get("subregions", {})

	map_subregion_option.add_item("Select a Subregion", 0)
	map_subregion_option.set_item_metadata(0, "")

	var idx = 1
	for subregion_id in subregions.keys():
		var subregion_data = subregions[subregion_id]
		var subregion_name = "Unknown Subregion"
		if subregion_data.has("names") and subregion_data.names.size() > 0 and subregion_data.names[0]:
			subregion_name = subregion_data.names[0]
		map_subregion_option.add_item(subregion_name, idx)
		map_subregion_option.set_item_metadata(idx, subregion_id)
		idx += 1

func _on_map_subregion_selected(index: int) -> void:
	current_selected_subregion = map_subregion_option.get_item_metadata(index)
	
	for child in map_content.get_children():
		if child != map_image:
			map_content.remove_child(child)
			child.queue_free()

	if current_selected_subregion == "" or current_selected_region == "" or current_selected_world == "":
		return

	var world_data = game_data_worlds.get(current_selected_world, {})
	var regions = world_data.get("regions", {})
	var region_data = regions.get(current_selected_region, {})
	var subregions = region_data.get("subregions", {})
	var subregion_data = subregions.get(current_selected_subregion, {})
	var dungeons = subregion_data.get("dungeons", {})

	var dungeon_ids = []
	if dungeons is Dictionary:
		dungeon_ids = dungeons.keys()
	elif dungeons is Array:
		dungeon_ids = dungeons
	elif dungeons is String:
		dungeon_ids = [dungeons]

	for dungeon_id in dungeon_ids:
		var dungeon_data = game_data_dungeons.get(str(dungeon_id), {})
		if dungeon_data.is_empty():
			continue

		var pos = dungeon_data.get("position", [0, 0])
		var x = pos[0]
		var y = pos[1]

		var icon_name = dungeon_data.get("icon", "")
		var icon_path = "res://assets/map_icons/" + icon_name

		var btn = TextureButton.new()
		var tex = load(icon_path)
		if not tex:
			tex = load("res://icon.svg") # Fallback
		
		if tex:
			btn.texture_normal = tex
			btn.position = Vector2(x, y)
			
			var lbl = Label.new()
			var d_names = dungeon_data.get("names", [])
			if d_names.size() > 0 and d_names[0]:
				lbl.text = d_names[0]
			else:
				lbl.text = "Unknown Dungeon"
			
			lbl.position = Vector2(-lbl.get_minimum_size().x/2 + btn.size.x/2, btn.size.y)
			lbl.add_theme_font_size_override("font_size", 14)
			lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
			lbl.add_theme_constant_override("outline_size", 4)
			btn.add_child(lbl)
			
			btn.pressed.connect(_on_dungeon_clicked.bind(str(dungeon_id)))
			map_content.add_child(btn)

func _on_dungeon_clicked(dungeon_id: String) -> void:
	var dungeon_data = game_data_dungeons.get(dungeon_id, {})
	var d_names = dungeon_data.get("names", [])
	if d_names.size() > 0 and d_names[0]:
		mission_dungeon_name.text = d_names[0]
	else:
		mission_dungeon_name.text = "Unknown Dungeon"

	for child in missions_list_container.get_children():
		missions_list_container.remove_child(child)
		child.queue_free()

	var dungeon_missions = dungeon_data.get("missions", {})
	var mission_ids = []
	if dungeon_missions is Dictionary:
		mission_ids = dungeon_missions.keys()
	elif dungeon_missions is Array:
		mission_ids = dungeon_missions
	elif dungeon_missions is String:
		mission_ids = [dungeon_missions]

	for mission_id in mission_ids:
		var mission_data = game_data_missions.get(str(mission_id), {})
		if mission_data.is_empty():
			continue
		
		var vbox = VBoxContainer.new()
		
		var name_lbl = Label.new()
		name_lbl.text = mission_data.get("name", "Unknown Mission")
		name_lbl.add_theme_font_size_override("font_size", 16)
		vbox.add_child(name_lbl)
		
		var cost_lbl = Label.new()
		cost_lbl.text = "Cost: %d %s" % [mission_data.get("cost", 0), mission_data.get("cost_type", "NRG")]
		cost_lbl.add_theme_font_size_override("font_size", 12)
		vbox.add_child(cost_lbl)
		
		var challenges = mission_data.get("challenges", [])
		if challenges.size() > 0:
			var ch_lbl = Label.new()
			ch_lbl.text = "Challenges:"
			ch_lbl.add_theme_font_size_override("font_size", 12)
			vbox.add_child(ch_lbl)
			for ch in challenges:
				var ch_item_lbl = Label.new()
				ch_item_lbl.text = "- " + ch.get("string", "")
				ch_item_lbl.add_theme_font_size_override("font_size", 10)
				vbox.add_child(ch_item_lbl)
				
		var sep = HSeparator.new()
		vbox.add_child(sep)

		var actions_hbox = HBoxContainer.new()
		var btn_start = Button.new()
		btn_start.text = "Start"
		btn_start.pressed.connect(_on_start_mission_pressed.bind(str(mission_id)))
		actions_hbox.add_child(btn_start)
		vbox.add_child(actions_hbox)
		
		missions_list_container.add_child(vbox)

	mission_details_popup.popup_centered()

	# Lazy load actual mission data
	var detailed_missions = await server_connection.get_dungeon_missions_async(mission_ids)
	if not mission_details_popup.visible:
		return # Closed before loading

	for child in missions_list_container.get_children():
		missions_list_container.remove_child(child)
		child.queue_free()

	for mission_id in mission_ids:
		var mission_data = detailed_missions.get(str(mission_id), {})
		if mission_data.is_empty():
			mission_data = game_data_missions.get(str(mission_id), {})
			if mission_data.is_empty():
				continue
		else:
			game_data_missions[str(mission_id)] = mission_data # Cache it

		var vbox = VBoxContainer.new()
		
		var name_lbl = Label.new()
		name_lbl.text = mission_data.get("name", "Unknown Mission")
		name_lbl.add_theme_font_size_override("font_size", 16)
		vbox.add_child(name_lbl)
		
		var cost_lbl = Label.new()
		cost_lbl.text = "Cost: %d %s" % [mission_data.get("cost", 0), mission_data.get("cost_type", "NRG")]
		cost_lbl.add_theme_font_size_override("font_size", 12)
		vbox.add_child(cost_lbl)
		
		var challenges = mission_data.get("challenges", [])
		if challenges.size() > 0:
			var ch_lbl = Label.new()
			ch_lbl.text = "Challenges:"
			ch_lbl.add_theme_font_size_override("font_size", 12)
			vbox.add_child(ch_lbl)
			for ch in challenges:
				var ch_item_lbl = Label.new()
				ch_item_lbl.text = "- " + ch.get("string", "")
				ch_item_lbl.add_theme_font_size_override("font_size", 10)
				vbox.add_child(ch_item_lbl)
				
		var sep = HSeparator.new()
		vbox.add_child(sep)

		var actions_hbox = HBoxContainer.new()
		var btn_start = Button.new()
		btn_start.text = "Start"
		btn_start.pressed.connect(_on_start_mission_pressed.bind(str(mission_id)))
		actions_hbox.add_child(btn_start)
		vbox.add_child(actions_hbox)
		
		missions_list_container.add_child(vbox)


func _on_start_mission_pressed(mission_id: String) -> void:
	var result = await server_connection.perform_mission_async(mission_id)
	if result.has("error"):
		print("Failed to start mission: ", result.error)
		# Optional: we could show an error label if we add one to the popup
	else:
		if result.has("stats"):
			var stats = result.stats
			current_rank = int(stats.get("rank", current_rank))
			current_xp = int(stats.get("xp", current_xp))
			current_nrg = int(stats.get("current_nrg", current_nrg))
			max_nrg = int(stats.get("max_nrg", max_nrg))
			nrg_regen_rate_seconds = int(stats.get("nrg_regen_rate_seconds", nrg_regen_rate_seconds))
			seconds_until_next_nrg = float(stats.get("seconds_until_next_nrg", seconds_until_next_nrg))
			_update_stats_ui()
		
		if result.has("wallet"):
			var wallet = JSON.parse_string(result.wallet) if result.wallet is String else result.wallet
			_update_wallet_ui(wallet)
		
		print("Mission started successfully!")
		# Optionally close the popup
		# mission_details_popup.hide()

func _on_add_potion_button_pressed() -> void:
	var result = await server_connection.buy_item_async("101000100", 1)
	if result.has("error"):
		print("Failed to buy potion: ", result.error)
		shop_feedback_label.text = result.error
	else:
		shop_feedback_label.text = "Potion purchased successfully!"
		if result.has("items"):
			owned_items = result.items
		if result.has("wallet"):
			var wallet = JSON.parse_string(result.wallet) if result.wallet is String else result.wallet
			_update_wallet_ui(wallet)

func _refresh_items_list() -> void:
	for child in items_list_container.get_children():
		items_list_container.remove_child(child)
		child.queue_free()

	if owned_items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No items owned."
		items_list_container.add_child(empty_label)
		return

	for item in owned_items:
		if not item is Dictionary:
			continue

		var item_id = item.get("item_id", "")
		var item_data: Dictionary = game_data_items.get(item_id, {})

		var hbox := HBoxContainer.new()
		items_list_container.add_child(hbox)

		var icon_name = item_data.get("icon", "")
		if icon_name != "":
			var tex_rect := TextureRect.new()
			var tex = load("res://assets/items/" + icon_name)
			if tex:
				tex_rect.texture = tex
				tex_rect.custom_minimum_size = Vector2(40, 40)
				tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			hbox.add_child(tex_rect)

		var label := Label.new()
		label.text = "%s x%d" % [item_data.get("name", "Unknown Item"), item.get("quantity", 0)]
		label.add_theme_font_size_override("font_size", 18)
		hbox.add_child(label)

func _on_summon_button_pressed() -> void:
	_hide_all_ui()
	summon_ui.show()

func _on_summon_close_overlay_button_pressed() -> void:
	summon_overlay.hide()

func _on_summon_perform_button_pressed() -> void:
	if game_data_units.is_empty():
		return

	var summoned_units = await server_connection.summon_units_async(3)
	owned_units_ids.append_array(summoned_units)

	for child in summon_results_list.get_children():
		summon_results_list.remove_child(child)
		child.queue_free()

	for unit_inst in summoned_units:
		var unit_id = unit_inst.get("unit_id", "")
		var unit_data: Dictionary = game_data_units.get(unit_id, {})
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label := Label.new()
		name_label.text = "%s (Rarity: %d★)" % [
			unit_data.get("name", "Unknown"),
			unit_inst.get("current_rarity", 1)
		]
		name_label.add_theme_font_size_override("font_size", 18)
		vbox.add_child(name_label)

		var separator := HSeparator.new()
		vbox.add_child(separator)

		summon_results_list.add_child(vbox)

	summon_overlay.show()


func _refresh_units_list() -> void:
	for child in units_list_container.get_children():
		units_list_container.remove_child(child)
		child.queue_free()

	if owned_units_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No units owned."
		units_list_container.add_child(empty_label)
		return

	for unit_inst in owned_units_ids:
		if not unit_inst is Dictionary:
			continue

		var unit_id = unit_inst.get("unit_id", "")
		var unit_data: Dictionary = game_data_units.get(unit_id, {})

		var container = VBoxContainer.new()
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.alignment = BoxContainer.ALIGNMENT_CENTER

		var tex_btn = TextureButton.new()
		var img_path = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_id
		var tex = load(img_path)
		if tex:
			tex_btn.texture_normal = tex

		# Set size properties
		tex_btn.custom_minimum_size = Vector2(80, 80)
		tex_btn.ignore_texture_size = true
		tex_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tex_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		tex_btn.pressed.connect(_show_unit_detail.bind(unit_inst))
		container.add_child(tex_btn)

		var name_label = Label.new()
		name_label.text = unit_data.get("name", "Unknown")
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 12)
		container.add_child(name_label)

		units_list_container.add_child(container)

func _show_unit_detail(unit_inst: Dictionary) -> void:
	_hide_all_ui()
	unit_detail_ui.show()

	var unit_id = unit_inst.get("unit_id", "")
	var unit_data: Dictionary = game_data_units.get(unit_id, {})
	
	unit_detail_name_label.text = unit_data.get("name", "Unknown")

	var img_path = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_id
	var tex = load(img_path)
	if tex:
		unit_detail_sprite.texture = tex
	else:
		unit_detail_sprite.texture = null

	var rarity = unit_inst.get("current_rarity", 1)
	var max_rarity = unit_data.get("rarity_max", 5)
	var stars = ""
	for i in range(rarity):
		stars += "★"
	for i in range(max_rarity - rarity):
		stars += "☆"
	unit_detail_rarity_label.text = stars

	var rarity_max_levels = {
		1: 15,
		2: 30,
		3: 40,
		4: 60,
		5: 80,
		6: 100,
		7: 120
	}

	var level = unit_inst.get("level", 1)
	var max_level = rarity_max_levels.get(int(rarity), 15)
	unit_detail_level_label.text = "Lvl %d/%d" % [level, max_level]

	var next_xp = unit_inst.get("next_xp", 0)
	unit_detail_next_xp_label.text = "next %d" % next_xp

	var entries = unit_data.get("entries", {})
	var entry = entries.get(str(unit_id), entries.get(str(rarity), {}))

	for key in entries.keys():
		if entries[key].get("rarity") == rarity:
			entry = entries[key]
			break

	var stats = entry.get("stats", {})
	var hp = 0
	var mp = 0
	var atk = 0
	var def_stat = 0
	var mag = 0
	var spr = 0

	if not stats.is_empty():
		for stat_name in ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]:
			var stat_arr = stats.get(stat_name, [0, 0])
			if stat_arr.size() >= 2:
				var min_stat = stat_arr[0]
				var max_stat = stat_arr[1]
				var current_stat = min_stat
				if max_level > 1:
					current_stat = min_stat + (level - 1) * float(max_stat - min_stat) / (max_level - 1)

				if stat_name == "HP": hp = round(current_stat)
				elif stat_name == "MP": mp = round(current_stat)
				elif stat_name == "ATK": atk = round(current_stat)
				elif stat_name == "DEF": def_stat = round(current_stat)
				elif stat_name == "MAG": mag = round(current_stat)
				elif stat_name == "SPR": spr = round(current_stat)

	unit_detail_hp_value.text = str(int(hp))
	unit_detail_mp_value.text = str(int(mp))
	unit_detail_atk_value.text = str(int(atk))
	unit_detail_def_value.text = str(int(def_stat))

	# Fallback values for missing stats based on user instruction
	unit_detail_mag_value.text = str(int(mag))
	unit_detail_spr_value.text = str(int(spr))

	# Disconnect previously bound signals to avoid duplicate calls
	for connection in unit_detail_add_xp_button.pressed.get_connections():
		unit_detail_add_xp_button.pressed.disconnect(connection["callable"])

	for connection in unit_detail_awaken_button.pressed.get_connections():
		unit_detail_awaken_button.pressed.disconnect(connection["callable"])

	var instance_id = unit_inst.get("instance_id", "")
	unit_detail_add_xp_button.pressed.connect(_on_unit_add_xp_pressed.bind(instance_id))
	unit_detail_awaken_button.pressed.connect(_on_unit_awaken_pressed.bind(instance_id))

func _on_unit_detail_back_button_pressed() -> void:
	unit_detail_ui.hide()
	units_ui.show()

func _on_unit_add_xp_pressed(instance_id: String) -> void:
	var result = await server_connection.add_unit_xp_async(instance_id, 1000)
	if result.has("error"):
		print("Failed to add XP: ", result.error)
	else:
		# Refresh full units list
		owned_units_ids = await server_connection.read_player_units_async()
		_refresh_units_list()
		# Re-render detail page with updated data if it's currently showing
		if unit_detail_ui.visible:
			for unit in owned_units_ids:
				if unit.get("instance_id") == instance_id:
					_show_unit_detail(unit)
					break

func _on_unit_awaken_pressed(instance_id: String) -> void:
	var result = await server_connection.awaken_unit_async(instance_id)
	if result.has("error"):
		print("Failed to awaken: ", result.error)
	else:
		# Refresh full units list
		owned_units_ids = await server_connection.read_player_units_async()
		_refresh_units_list()
		# Re-render detail page with updated data if it's currently showing
		if unit_detail_ui.visible:
			for unit in owned_units_ids:
				if unit.get("instance_id") == instance_id:
					_show_unit_detail(unit)
					break

func _on_add_friend_button_pressed() -> void:
	var username: String = add_friend_input.text.strip_edges()

	if username.is_empty():
		friends_feedback_label.text = "Username cannot be empty."
		return

	friends_feedback_label.text = "Adding friend..."

	var result: int = await(server_connection.add_friends_async(username))

	if result == OK:
		friends_feedback_label.text = "Friend request sent/accepted!"
		add_friend_input.text = ""
		_refresh_friends_list()
	elif result == ERR_UNAUTHORIZED:
		friends_feedback_label.text = "Not authorized."
	elif result == 3: # Invalid argument, usually means username not found or trying to add self
		friends_feedback_label.text = "User not found or invalid."
	else:
		friends_feedback_label.text = "Failed to add friend. Code: %d" % result

func _refresh_friends_list() -> void:
	for child in friends_list_container.get_children():
		friends_list_container.remove_child(child)
		child.queue_free()

	var friends_list: NakamaAPI.ApiFriendList = await(server_connection.list_friends_async())

	if friends_list == null:
		var err_label := Label.new()
		err_label.text = "Failed to load friends."
		friends_list_container.add_child(err_label)
		return

	if friends_list.friends.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No friends yet."
		friends_list_container.add_child(empty_label)
		return

	for friend_obj in friends_list.friends:
		var friend: NakamaAPI.ApiFriend = friend_obj as NakamaAPI.ApiFriend
		var hbox := HBoxContainer.new()
		var label := Label.new()
		var state_str := "Unknown"

		# State: 0 = Friend, 1 = Invite sent, 2 = Invite received, 3 = Blocked
		match friend.state:
			0: state_str = "Friend"
			1: state_str = "Invite Sent"
			2: state_str = "Invite Received"
			3: state_str = "Blocked"

		label.text = "%s (%s)" % [friend.user.username, state_str]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)

		if friend.state == 0:
			var delete_btn := Button.new()
			delete_btn.text = "Delete"
			delete_btn.pressed.connect(_on_delete_friend_pressed.bind(friend.user.username))
			hbox.add_child(delete_btn)
		elif friend.state == 1:
			var undo_btn := Button.new()
			undo_btn.text = "Undo"
			undo_btn.pressed.connect(_on_undo_request_pressed.bind(friend.user.username))
			hbox.add_child(undo_btn)
		elif friend.state == 2:
			var accept_btn := Button.new()
			accept_btn.text = "Accept"
			accept_btn.pressed.connect(_on_accept_request_pressed.bind(friend.user.username))
			hbox.add_child(accept_btn)
			var decline_btn := Button.new()
			decline_btn.text = "Decline"
			decline_btn.pressed.connect(_on_decline_request_pressed.bind(friend.user.username))
			hbox.add_child(decline_btn)

		friends_list_container.add_child(hbox)

func _on_delete_friend_pressed(username: String) -> void:
	friends_feedback_label.text = "Deleting friend..."
	var result: int = await(server_connection.delete_friends_async(username))
	if result == OK:
		friends_feedback_label.text = "Friend deleted."
		_refresh_friends_list()
	else:
		friends_feedback_label.text = "Failed to delete friend. Code: %d" % result

func _on_undo_request_pressed(username: String) -> void:
	friends_feedback_label.text = "Undoing friend request..."
	var result: int = await(server_connection.delete_friends_async(username))
	if result == OK:
		friends_feedback_label.text = "Friend request undone."
		_refresh_friends_list()
	else:
		friends_feedback_label.text = "Failed to undo request. Code: %d" % result

func _on_accept_request_pressed(username: String) -> void:
	friends_feedback_label.text = "Accepting friend request..."
	var result: int = await(server_connection.add_friends_async(username))
	if result == OK:
		friends_feedback_label.text = "Friend request accepted."
		_refresh_friends_list()
	else:
		friends_feedback_label.text = "Failed to accept request. Code: %d" % result

func _on_decline_request_pressed(username: String) -> void:
	friends_feedback_label.text = "Declining friend request..."
	var result: int = await(server_connection.delete_friends_async(username))
	if result == OK:
		friends_feedback_label.text = "Friend request declined."
		_refresh_friends_list()
	else:
		friends_feedback_label.text = "Failed to decline request. Code: %d" % result


func _on_edit_update_button_pressed() -> void:
	var new_username: String = edit_new_username_input.text.strip_edges()

	if new_username.is_empty():
		edit_feedback_label.text = "Username cannot be empty."
		return

	edit_feedback_label.text = "Updating profile..."

	var result: int = await(server_connection.update_account_async(new_username))

	if result == OK:
		edit_feedback_label.text = "Update successful!"
		edit_profile_ui.hide()
		game_ui.show()
		bottom_nav.show()

		var account = await(server_connection.get_account_async())
		if account and account.user.username != "":
			user_info_label.text = account.user.username
	else:
		edit_feedback_label.text = "Update failed. Error code: %d" % result

func _on_logout_pressed() -> void:
	server_connection.logout()
	_hide_all_ui()
	bottom_nav.hide()
	login_ui.show()
	user_info_label.text = ""
	login_feedback_label.text = "Logged out successfully."

func _on_go_to_register_button_pressed() -> void:
	login_ui.hide()
	register_ui.show()

func _on_back_to_login_button_pressed() -> void:
	register_ui.hide()
	login_ui.show()

func _on_login_button_pressed() -> void:
	var email: String = login_email_input.text.strip_edges()
	var password: String = login_password_input.text.strip_edges()
	
	if email.is_empty() or password.is_empty():
		login_feedback_label.text = "Email and Password are required."
		return

	login_feedback_label.text = "Logging in..."

	var result: int = await(server_connection.authenticate_async(email, password))
	
	if result == OK:
		login_feedback_label.text = "Login successful!"
		_transition_to_game(email)
	else:
		login_feedback_label.text = "Login failed. Error code: %d" % result

func _on_register_button_pressed() -> void:
	var username: String = register_username_input.text.strip_edges()
	var email: String = register_email_input.text.strip_edges()
	var password: String = register_password_input.text.strip_edges()

	if username.is_empty() or email.is_empty() or password.is_empty():
		register_feedback_label.text = "Username, Email, and Password are required."
		return

	register_feedback_label.text = "Registering..."

	var result: int = await(server_connection.register_async(email, password, username))

	if result == OK:
		register_feedback_label.text = "Registration successful!"
		_transition_to_game(email)
	else:
		register_feedback_label.text = "Registration failed. Error code: %d" % result

func _transition_to_game(email: String) -> void:
	login_ui.hide()
	register_ui.hide()
	game_ui.show()
	bottom_nav.show()
	top_header.show()
	user_menu_button.show()

	var stats = await server_connection.read_player_stats_async()
	current_rank = int(stats.get("rank", 1))
	current_xp = int(stats.get("xp", 0))
	next_rank_xp = int(stats.get("next_rank_xp", 100))
	current_nrg = int(stats.get("current_nrg", 41))
	max_nrg = int(stats.get("max_nrg", 41))
	nrg_regen_rate_seconds = int(stats.get("nrg_regen_rate_seconds", 300))
	seconds_until_next_nrg = float(stats.get("seconds_until_next_nrg", 0.0))
	_update_stats_ui()

	owned_units_ids = await server_connection.read_player_units_async()
	owned_items = await server_connection.read_player_items_async()

	if not AssetPatcher.patch_complete.is_connected(_on_patch_complete):
		AssetPatcher.patch_progress.connect(func(file_name, status):
			print("Patching ", file_name, ": ", status)
		)
		AssetPatcher.patch_complete.connect(_on_patch_complete.bind(email))
		
	AssetPatcher.start_patching()
	await AssetPatcher.patch_complete

func _on_patch_complete(email: String = ""):
	print("Patching complete!")
	game_data_units = AssetPatcher.get_data("units")
	game_data_items = AssetPatcher.get_data("items")
	game_data_weapons = AssetPatcher.get_data("weapons")
	game_data_worlds = AssetPatcher.get_data("worlds")
	game_data_dungeons = AssetPatcher.get_data("dungeons")
	
	
	# Update shop potion UI dynamically
	var potion_data = game_data_items.get("101000100", {})
	if potion_data:
		shop_potion_name.text = potion_data.get("name", "Potion")
		var strings = potion_data.get("strings", {})
		var desc_short_list = strings.get("desc_short", [])
		if desc_short_list and desc_short_list.size() > 0:
			shop_potion_desc.text = desc_short_list[0]
		var icon_name = potion_data.get("icon", "")
		if icon_name != "":
			var tex = load("res://assets/items/" + icon_name)
			if tex:
				shop_potion_icon.texture = tex

	user_info_label.text = "Loading..."

	var account = await(server_connection.get_account_async())
	if account:
		if account.user.username != "":
			user_info_label.text = account.user.username 
		else:
			user_info_label.text = email

		var wallet_str = account.wallet
		if wallet_str and wallet_str != "":
			var wallet = JSON.parse_string(wallet_str)
			if wallet and wallet is Dictionary:
				_update_wallet_ui(wallet)
		else:
			_update_wallet_ui({})
	else:
		_update_wallet_ui({})
