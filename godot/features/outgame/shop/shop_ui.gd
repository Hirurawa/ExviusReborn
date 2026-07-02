extends Control

enum Tab { ITEMS, AWAKENING, PRISMS, EQUIPMENTS }

# Hand-curate the contents of each shop tab. Awakening / Prism tabs are
# intentionally empty — populate with the IDs you want offered for sale.
@export var tab_items_ids: Array[String] = ["101000100", "101001100"]
@export var tab_awakening_ids: Array[String] = ["106301900", "106302000", "106302100", "106302200", "106302300", "106302600", "290010000", "290010100", "290010200", "290020000", "290020100", "290020200", "290020300", "290020400", "290020500", "290020600", "290020700", "290020800", "290020900", "290030000", "290030100", "290030200", "290030300", "290030400", "290030500", "290030600", "290030700", "290030800", "290030900", "290031000", "290040000", "290040100", "290040200", "290040300", "290040400", "290050100", "290050200", "290050300", "290050400", "290050500", "290060000", "290060100", "290060200", "290060300", "290060400", "291000100", "291000200", "291000300", "291000400", "291000500", "291100100", "291100200", "291100300", "292000100", "292000200", "292000300", "292000400", "292000500", "292000600", "293000100", "293000200", "1209000845", "1209002041"]
@export var tab_prism_ids: Array[String] = ["300000010", "300000020", "300000030", "300000040", "300000050", "300000060", "300000070", "300000080", "300000090", "300000100", "300000110", "300000120", "300000130", "300000140", "300000150", "300000160", "300000170", "300000180", "300000190", "300000200", "300000210", "300000220", "300000230", "300000240", "300000250", "300000260", "300000270", "300000280", "300000290", "300000300", "300000310", "300000320", "300000330", "300000340", "300000350", "300000360", "300000370", "300000380", "300000390", "300000400", "300000410", "300000420", "300000430", "300000440", "300000450", "300000460", "300000470", "300000480", "300000490", "300000500", "300000510", "300000520", "300000530", "300000540", "300000550", "300000560", "300000570", "300000580", "300000590", "300000600", "300000620", "300000630", "300000640", "300000650", "300000660", "300000670", "300000680", "300000690", "300000700", "300000710", "300000720", "300000730", "300000740", "300000750", "300000760", "300000770", "300000780", "300000790", "300000800", "300000810", "300000820", "300000830", "300000840", "300000850", "300000860", "300000870", "300000880", "300000890", "300000900", "300000910", "300000920", "300000930", "300000940", "300000950", "300000960", "300000970", "300000980", "300000990", "300001000", "300001010", "300001020", "300001030", "300001040", "300001050", "300001060", "300001070", "300001080", "300001090", "300001100", "300001110", "300001120", "300001130", "300001150", "300001160", "300001170", "300001180", "300001190", "300001200", "300001210", "300001230", "300001240", "300001250", "300001260", "300001300", "300001310", "300001340", "300001350", "300001360", "300001370", "300001380", "300001390", "300001400", "300001410", "300001420", "300001430", "300001440", "300001450", "300001460", "300001470", "300001480", "300001490", "300001500", "300001510", "300001520", "300001530", "300001540", "300001550", "300001560", "300001580", "300001590", "300001610", "300001620", "300001630", "300001640", "300001680", "300001690", "300001700", "300001710", "300001750", "300001760", "300001770", "300001780", "300001790", "300001800", "300001860", "300001870", "300001880", "300001890", "300001900", "300001910", "300001920", "300001930", "300001940", "300001960", "300001970", "300002000", "300002010", "300002020", "300002030", "300002040", "300002050", "300002060", "300002070", "300002080", "300002090", "300002100", "300002140", "300002150", "300002170", "300002180", "300002190", "300002200", "300002210", "300002220", "300002230", "300002240", "300002250", "300002280", "300002290", "300002300", "300002310", "300002320", "300002330", "300002360", "300002370", "300002380", "300002390", "300002400", "300002410", "300002440", "300002450", "300002460", "300002470", "300002480", "300002490", "300002500", "300002520", "300002540", "300002550", "300002560", "300002570", "300002580", "300002590", "300002630", "300002640", "300002650", "300002660", "300002670", "300002680", "300002690", "300002710", "300002720", "300002740", "300002750", "300002760", "300002770", "300002780", "300002790", "300002800", "300002810", "300002850", "300002900", "300002910", "300002920", "300002930", "300002940", "300002950", "300002960", "300002970", "300002980", "300002990", "300003000", "300003010", "300003020", "300003030", "300003040", "300003050", "300003060", "300003070", "300003080", "300003090", "300003100", "300003110", "300003140", "300003150", "300003160", "300003170", "300003180", "300003190", "300003400", "300003600", "300003700", "300003800", "300003900", "300004000", "300004600", "300004700", "300005100", "300005200", "300005300", "300005400", "300005500", "300005600", "300005700", "310000010", "310000020", "310000030", "310000040", "310000050", "310000060", "310000070", "310000080", "310000090", "310000100", "310000110", "310000120", "310000130", "310000140", "310000160", "310000170", "310000180", "310000190", "310000200", "310000210", "310000220", "310000230", "310000240", "310000250", "310000260", "310000270", "310000280", "310000290", "310000300", "310000310", "310000320", "310000330", "310000340", "310000350", "310000360", "310000370", "310000380", "310000390", "310000400", "310000410", "310000411", "310000412", "310000414", "310000420", "310000430", "310000440", "310000450", "310000460", "310000470", "310000480", "310000490", "310000500", "310000510", "310000520", "310000530", "310000540", "310000550", "310000560", "310000570", "310000580"]
@export var tab_equipment_ids: Array[String] = ["301000200", "403043300", "405000200"]

@onready var shop_feedback_label: Label = $VBoxContainer/ShopFeedbackLabel
@onready var list_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer/ListContainer
@onready var scroll_container: ScrollContainer = $VBoxContainer/ScrollContainer
@onready var items_tab_button: TextureButton = $VBoxContainer/HBoxContainer/Items
@onready var awakening_tab_button: TextureButton = $VBoxContainer/HBoxContainer/AwakeningMaterials
@onready var prisms_tab_button: TextureButton = $VBoxContainer/HBoxContainer/Prisms
@onready var equipments_tab_button: TextureButton = $VBoxContainer/HBoxContainer/Equipments
@onready var search_bar: Control = $VBoxContainer/SearchBar
@onready var search_input: LineEdit = $VBoxContainer/SearchBar/SearchInput
@onready var search_clear_button: Button = $VBoxContainer/SearchBar/ClearButton
@onready var item_row_template: PackedScene = preload("res://features/outgame/shop/ShopItemRow.tscn")

const TAB_TEXTURE_INACTIVE: Texture2D = preload("res://assets/ui/create/cre_btn4_1.tres")
const TAB_TEXTURE_ACTIVE: Texture2D = preload("res://assets/ui/create/cre_btn4_2.tres")

const SEARCH_BAR_EXPANDED_H: float = 56.0
const PULL_REVEAL_THRESHOLD_PX: float = 40.0
const PULL_COLLAPSE_THRESHOLD_PX: float = 40.0
const REVEAL_TWEEN_TIME: float = 0.18
const SEARCH_DEBOUNCE_SEC: float = 0.15

var _current_tab: int = Tab.ITEMS
var _search_query: String = ""
var _search_bar_expanded: bool = false
var _pull_accumulator: float = 0.0
var _search_debounce_timer: Timer = null
var _search_reveal_tween: Tween = null

func _ready() -> void:
	InventoryService.purchase_successful.connect(_on_purchase_successful)
	InventoryService.purchase_failed.connect(_on_purchase_failed)
	items_tab_button.pressed.connect(_select_tab.bind(Tab.ITEMS))
	awakening_tab_button.pressed.connect(_select_tab.bind(Tab.AWAKENING))
	prisms_tab_button.pressed.connect(_select_tab.bind(Tab.PRISMS))
	equipments_tab_button.pressed.connect(_select_tab.bind(Tab.EQUIPMENTS))
	_setup_search_bar()
	_select_tab(Tab.ITEMS)

func _select_tab(tab: int) -> void:
	_current_tab = tab
	_refresh_tab_button_textures()
	_populate_for_current_tab()

func _refresh_tab_button_textures() -> void:
	var active: TextureButton = _active_tab_button()
	for button in [items_tab_button, awakening_tab_button, prisms_tab_button, equipments_tab_button]:
		var is_active: bool = button == active
		button.texture_normal = TAB_TEXTURE_ACTIVE if is_active else TAB_TEXTURE_INACTIVE
		button.texture_focused = button.texture_normal
		button.texture_hover = button.texture_normal
		button.texture_pressed = button.texture_normal

func _active_tab_button() -> TextureButton:
	match _current_tab:
		Tab.AWAKENING:
			return awakening_tab_button
		Tab.PRISMS:
			return prisms_tab_button
		Tab.EQUIPMENTS:
			return equipments_tab_button
		_:
			return items_tab_button

func _populate_for_current_tab() -> void:
	match _current_tab:
		Tab.ITEMS:
			_populate_shop(tab_items_ids, list_container, "items")
		Tab.AWAKENING:
			_populate_shop(tab_awakening_ids, list_container, "items")
		Tab.PRISMS:
			_populate_shop(tab_prism_ids, list_container, "items")
		Tab.EQUIPMENTS:
			_populate_shop(tab_equipment_ids, list_container, "equipments")

func _populate_shop(ids: Array, container: Control, type: String) -> void:
	for child in container.get_children():
		child.queue_free()

	var matched_count: int = 0
	for id in ids:
		var data: Dictionary = GameDatabase.get_item(id)
		if data.is_empty():
			data = GameDatabase.get_equipment(id)

		if data.is_empty():
			continue
		if not _entry_matches_search_query(data):
			continue

		var row = item_row_template.instantiate()
		container.add_child(row)
		row.setup(id, data, type)
		row.buy_requested.connect(_on_buy_requested)
		matched_count += 1

	if matched_count == 0 and _search_query != "":
		var empty_label := Label.new()
		empty_label.text = "No items match '%s'." % _search_query
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		container.add_child(empty_label)

func _entry_matches_search_query(data: Dictionary) -> bool:
	if _search_query == "":
		return true
	var name_text: String = str(data.get("name", "")).to_lower()
	return name_text.find(_search_query) != -1

func _setup_search_bar() -> void:
	if search_bar == null:
		return

	search_bar.custom_minimum_size = Vector2(search_bar.custom_minimum_size.x, 0.0)
	search_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_search_bar_expanded = false
	_pull_accumulator = 0.0
	_search_query = ""

	if search_input != null:
		search_input.text = ""
		search_input.placeholder_text = "Filter by name"
		if not search_input.text_changed.is_connected(_on_search_text_changed):
			search_input.text_changed.connect(_on_search_text_changed)
		if not search_input.text_submitted.is_connected(_on_search_text_submitted):
			search_input.text_submitted.connect(_on_search_text_submitted)

	if search_clear_button != null:
		if not search_clear_button.pressed.is_connected(_on_search_clear_pressed):
			search_clear_button.pressed.connect(_on_search_clear_pressed)

	if _search_debounce_timer == null:
		_search_debounce_timer = Timer.new()
		_search_debounce_timer.one_shot = true
		_search_debounce_timer.wait_time = SEARCH_DEBOUNCE_SEC
		_search_debounce_timer.timeout.connect(_apply_search_query)
		add_child(_search_debounce_timer)

	if scroll_container != null and not scroll_container.gui_input.is_connected(_on_scroll_gui_input):
		scroll_container.gui_input.connect(_on_scroll_gui_input)

func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_pull_accumulator = 0.0
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if not st.pressed:
			_pull_accumulator = 0.0
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_process_pull_delta(mm.relative.y)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_process_pull_delta(sd.relative.y)

func _process_pull_delta(delta_y: float) -> void:
	if scroll_container == null:
		return
	if scroll_container.scroll_vertical > 0:
		_pull_accumulator = 0.0
		return

	if not _search_bar_expanded:
		if delta_y > 0.0:
			_pull_accumulator += delta_y
			if _pull_accumulator >= PULL_REVEAL_THRESHOLD_PX:
				_pull_accumulator = 0.0
				_expand_search_bar()
		else:
			_pull_accumulator = 0.0
		return

	if _search_query != "":
		_pull_accumulator = 0.0
		return

	if delta_y < 0.0:
		_pull_accumulator += -delta_y
		if _pull_accumulator >= PULL_COLLAPSE_THRESHOLD_PX:
			_pull_accumulator = 0.0
			_collapse_search_bar()
	else:
		_pull_accumulator = 0.0

func _expand_search_bar() -> void:
	if _search_bar_expanded or search_bar == null:
		return
	_search_bar_expanded = true
	_tween_search_bar_height(SEARCH_BAR_EXPANDED_H, Tween.EASE_OUT)
	if search_input != null:
		search_input.grab_focus()

func _collapse_search_bar() -> void:
	if not _search_bar_expanded or search_bar == null:
		return
	_search_bar_expanded = false
	if search_input != null:
		search_input.release_focus()
	_tween_search_bar_height(0.0, Tween.EASE_IN)

func _tween_search_bar_height(target_h: float, ease_mode: int) -> void:
	if _search_reveal_tween != null and _search_reveal_tween.is_running():
		_search_reveal_tween.kill()
	_search_reveal_tween = create_tween()
	_search_reveal_tween.tween_property(
		search_bar,
		"custom_minimum_size:y",
		target_h,
		REVEAL_TWEEN_TIME
	).set_trans(Tween.TRANS_SINE).set_ease(ease_mode)

func _on_search_text_changed(_new_text: String) -> void:
	if _search_debounce_timer != null:
		_search_debounce_timer.start()

func _on_search_text_submitted(_new_text: String) -> void:
	if _search_debounce_timer != null:
		_search_debounce_timer.stop()
	_apply_search_query()

func _on_search_clear_pressed() -> void:
	if search_input == null:
		return
	if search_input.text == "" and _search_query == "":
		return
	search_input.text = ""
	if _search_debounce_timer != null:
		_search_debounce_timer.stop()
	if _search_query != "":
		_search_query = ""
		_populate_for_current_tab()

func _apply_search_query() -> void:
	if search_input == null:
		return
	var normalized: String = search_input.text.strip_edges().to_lower()
	if normalized == _search_query:
		return
	_search_query = normalized
	_populate_for_current_tab()

func _on_buy_requested(id: String, type: String, quantity: int) -> void:
	InventoryService.request_buy_item(id, quantity)

func _on_purchase_successful() -> void:
	shop_feedback_label.text = "Item purchased successfully!"
	_populate_for_current_tab()

func _on_purchase_failed(error_message: String) -> void:
	shop_feedback_label.text = _friendly_purchase_error(error_message)

func _friendly_purchase_error(error_message: String) -> String:
	match error_message:
		"ERR_INSUFFICIENT_RESOURCES", "ERR_INSUFFICENT_RESOURCES":
			return "Not enough gil to purchase this item."
		"ERR_MISSING_SERVER_ERROR_MSG":
			return "Purchase failed. Please try again."
		_:
			return "Purchase failed: %s" % error_message
