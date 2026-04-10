extends PanelContainer

@onready var home_button: Button = $HBox/HomeButton
@onready var units_button: Button = $HBox/UnitsButton
@onready var items_button: Button = $HBox/ItemsButton
@onready var shop_button: Button = $HBox/ShopButton
@onready var summon_button: Button = $HBox/SummonButton
@onready var friends_button: Button = $HBox/FriendsButton

func _ready() -> void:
	home_button.pressed.connect(func(): UIManager.set_root("game_ui"))
	units_button.pressed.connect(func(): UIManager.set_root("units_ui"))
	items_button.pressed.connect(func(): UIManager.set_root("items_ui"))
	shop_button.pressed.connect(func(): UIManager.set_root("shop_ui"))
	summon_button.pressed.connect(func(): UIManager.set_root("summon_ui"))
	friends_button.pressed.connect(func(): UIManager.set_root("friends_ui"))
