extends Node
## ButtonSoundInstaller — autoload that auto-attaches click SFX to every
## `BaseButton` added to the scene tree.
##
## Default sound is `SFX_OK`. If the button's node name (case-insensitive)
## matches one of `BACK_NAME_PATTERNS`, `SFX_NO` plays instead.
##
## Per-button opt-out: set a meta `no_click_sfx = true` on any button.
## Per-button override: set meta `click_sfx = "res://..."` to play a custom
## sound.

const SFX_OK: String = "res://assets/audio/sfx/se_system_common_ok_1.wav"
const SFX_NO: String = "res://assets/audio/sfx/se_system_common_no_1.wav"

const BACK_NAME_PATTERNS: Array[String] = [
	"back", "close", "cancel", "exit", "no",
]

const META_DISABLE: StringName = &"no_click_sfx"
const META_OVERRIDE: StringName = &"click_sfx"
const META_INSTALLED: StringName = &"_click_sfx_installed"


func _ready() -> void:
	# Catch every future button.
	get_tree().node_added.connect(_on_node_added)
	# Catch buttons that already exist (e.g. autoloaded UI overlays).
	_install_recursive(get_tree().root)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_install(node)


func _install_recursive(root: Node) -> void:
	if root is BaseButton:
		_install(root)
	for child in root.get_children():
		_install_recursive(child)


func _install(button: BaseButton) -> void:
	if button.has_meta(META_INSTALLED):
		return
	button.set_meta(META_INSTALLED, true)
	# Defer the connection so user-set metadata (assigned after instantiation
	# but before _ready) is in place when we check it.
	button.pressed.connect(_on_button_pressed.bind(button))


func _on_button_pressed(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	if button.has_meta(META_DISABLE) and bool(button.get_meta(META_DISABLE)):
		return

	var path: String = SFX_OK
	if button.has_meta(META_OVERRIDE):
		path = String(button.get_meta(META_OVERRIDE))
	elif _is_back_button(button):
		path = SFX_NO

	if path.is_empty():
		return
	AudioService.play_ui(path)


func _is_back_button(button: BaseButton) -> bool:
	var name_lc: String = String(button.name).to_lower()
	for pattern in BACK_NAME_PATTERNS:
		if name_lc.find(pattern) != -1:
			return true
	return false
