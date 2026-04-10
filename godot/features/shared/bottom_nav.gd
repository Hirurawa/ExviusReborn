extends PanelContainer

@onready var home_button = $HBox/HomeButton
@onready var units_button = $HBox/UnitsButton
@onready var items_button = $HBox/ItemsButton
@onready var shop_button = $HBox/ShopButton
@onready var summon_button = $HBox/SummonButton
@onready var friends_button = $HBox/FriendsButton

func _ready():
	home_button.pressed.connect(func(): UIManager.set_root("game_ui"))
	units_button.pressed.connect(func(): UIManager.set_root("units_ui"))
	items_button.pressed.connect(func(): UIManager.set_root("items_ui"))
	shop_button.pressed.connect(func(): UIManager.set_root("shop_ui"))
	summon_button.pressed.connect(func(): UIManager.set_root("summon_ui"))
	friends_button.pressed.connect(func(): UIManager.set_root("friends_ui"))
