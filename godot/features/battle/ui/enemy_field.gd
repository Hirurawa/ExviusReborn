class_name EnemyField
extends Control

## The enemy half of the battle screen, on %EnemyRegion: one view per enemy of the
## current wave, keyed by combatant id (a wrapper holding the sprite, its damage
## numbers and the target arrow), placed from the formation's dispPos. It shows the
## chosen target's arrow, hit shakes, the death tween, drop icons and an enemy in the air
## (a jump), and reports taps (pick a target) and long presses (enemy info). The battle
## screen pushes everything in.

signal enemy_tapped(enemy_id: int)
signal enemy_long_pressed(enemy_id: int)

const TargetArrowTexture: Texture2D = preload("res://assets/ui/common/mini_arrow_b.tres")
const FALLBACK_ICON: String = "res://icon.svg"

## `dispPos` values (BATTLE_GROUP) are authored in an abstract field, observed roughly
## x 110-260 and y 206-426; they map proportionally into the region as if it were this
## size. Changing it shifts and scales the whole arrangement.
const DISP_REFERENCE: Vector2 = Vector2(320, 480)
const WRAPPER_SIZE: Vector2 = Vector2(140, 140)
## Used while the region has no size yet (the first frame).
const REGION_FALLBACK_SIZE: Vector2 = Vector2(360, 400)

const DEATH_FADE_SECONDS: float = 0.4
const DEATH_SHAKE_OFFSET: float = 15.0
const DEATH_SHAKE_LOOPS: int = 4
const DROP_SECONDS: float = 0.6
const DROP_HOLD_SECONDS: float = 0.5
const DROP_FADE_SECONDS: float = 0.3
const DROP_DISTANCE: Vector2 = Vector2(60.0, 40.0)
## How far an enemy in the air (a jump) rises while it fades out, and how long it takes.
const AWAY_RISE: Vector2 = Vector2(0, -200)
const AWAY_MOVE_SECONDS: float = 0.25

## Where drop icons fly (the screen's root, above the fields).
var overlay: Control = null

@onready var _container: Control = $EnemiesContainer

## Enemy id -> { wrapper, sprite, damage, arrow }.
var _views: Dictionary = {}
## Enemy id -> its wrapper's position before it left the field, for the enemies in the air.
var _away: Dictionary = {}
var _damage_numbers: DamageNumberSpawner
var _texture_cache: Dictionary = {}


func _ready() -> void:
	_damage_numbers = DamageNumberSpawner.new(self)


func _exit_tree() -> void:
	_texture_cache.clear()
	_damage_numbers.clear_pool()


## Replaces the views with one per enemy, in formation order: each { id, template_id
## (the monster id the sprites are filed under), disp_pos }. No arrow shows until
## set_target().
func build(enemies: Array) -> void:
	clear()
	for slot in range(enemies.size()):
		var enemy: Dictionary = enemies[slot]
		var enemy_id: int = int(enemy["id"])
		var wrapper := Control.new()
		wrapper.name = "EnemyWrapper_%d" % slot
		wrapper.custom_minimum_size = WRAPPER_SIZE
		wrapper.size = WRAPPER_SIZE
		wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
		wrapper.position = _wrapper_position(enemy.get("disp_pos", Vector2.ZERO))
		_container.add_child(wrapper)

		var sprite := CombatSprite.new()
		sprite.name = "EnemyCombatSprite_%d" % slot
		sprite.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
		wrapper.add_child(sprite)
		sprite.setup(enemy_id, str(enemy.get("template_id", "")), true)
		sprite.short_tapped.connect(enemy_tapped.emit)
		sprite.long_pressed.connect(enemy_long_pressed.emit)

		var damage := Control.new()
		damage.name = "DamageContainer"
		damage.set_anchors_preset(Control.PRESET_FULL_RECT)
		damage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(damage)

		var arrow := TextureRect.new()
		arrow.name = "TargetArrow"
		arrow.texture = TargetArrowTexture
		arrow.custom_minimum_size = Vector2(48, 28)
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arrow.anchor_left = 0.5
		arrow.anchor_right = 0.5
		arrow.offset_left = -24
		arrow.offset_right = 24
		arrow.offset_top = -32
		arrow.offset_bottom = -4
		arrow.visible = false
		wrapper.add_child(arrow)

		_views[enemy_id] = {"wrapper": wrapper, "sprite": sprite, "damage": damage, "arrow": arrow}


func clear() -> void:
	for child in _container.get_children():
		_container.remove_child(child)
		child.queue_free()
	_views.clear()
	_away.clear()


func has_view(enemy_id: int) -> bool:
	return _views.has(enemy_id)


## Puts the target arrow over `enemy_id` (none for -1).
func set_target(enemy_id: int) -> void:
	for view_id in _views:
		(_views[view_id]["arrow"] as TextureRect).visible = view_id == enemy_id


## An enemy in the air (a jump, BattleStatus.AWAY): it rises and fades out of sight, its
## arrow with it; it drops back when it lands.
func set_away(enemy_id: int, away: bool) -> void:
	if not _views.has(enemy_id) or _away.has(enemy_id) == away:
		return
	var wrapper: Control = _views[enemy_id]["wrapper"]
	if away:
		_away[enemy_id] = wrapper.position
	var home: Vector2 = _away.get(enemy_id, wrapper.position)
	if not away:
		_away.erase(enemy_id)
	var tween: Tween = create_tween().bind_node(wrapper).set_parallel()
	tween.tween_property(wrapper, "position", home + AWAY_RISE if away else home, AWAY_MOVE_SECONDS)
	tween.tween_property(wrapper, "modulate:a", 0.0 if away else 1.0, AWAY_MOVE_SECONDS)


## Whether `enemy_id` shows as in the air.
func is_away(enemy_id: int) -> bool:
	return _away.has(enemy_id)


## A hit: the sprite shakes and the damage floats up.
func show_hit(enemy_id: int, amount: int) -> void:
	if not _views.has(enemy_id):
		return
	BattleTweens.shake(_views[enemy_id]["sprite"])
	_damage_numbers.spawn(amount, _views[enemy_id]["damage"])


func play_attack(enemy_id: int) -> void:
	if _views.has(enemy_id):
		(_views[enemy_id]["sprite"] as CombatSprite).play_action(CombatSprite.AnimState.ATK)


## The enemy shakes and fades out; its arrow goes.
func play_death(enemy_id: int) -> void:
	if not _views.has(enemy_id):
		return
	var sprite: CombatSprite = _views[enemy_id]["sprite"]
	(_views[enemy_id]["arrow"] as TextureRect).visible = false
	BattleTweens.kill(sprite, "shake_tween")
	BattleTweens.kill(sprite, "fade_tween")
	var orig_x: float = BattleTweens.orig_x(sprite)

	var fade_tween: Tween = create_tween()
	sprite.set_meta("fade_tween", fade_tween)
	fade_tween.tween_property(sprite, "modulate:a", 0.0, DEATH_FADE_SECONDS)
	fade_tween.tween_callback(sprite.hide)

	var shake_tween: Tween = create_tween()
	sprite.set_meta("shake_tween", shake_tween)
	shake_tween.set_loops(DEATH_SHAKE_LOOPS)
	shake_tween.tween_property(sprite, "position:x", orig_x - DEATH_SHAKE_OFFSET, BattleTweens.SHAKE_STEP_SECONDS)
	shake_tween.tween_property(sprite, "position:x", orig_x + DEATH_SHAKE_OFFSET, BattleTweens.SHAKE_STEP_SECONDS)
	shake_tween.finished.connect(func() -> void: sprite.position.x = orig_x)


## An enemy back from KO shows again.
func play_revive(enemy_id: int) -> void:
	if not _views.has(enemy_id):
		return
	var sprite: CombatSprite = _views[enemy_id]["sprite"]
	BattleTweens.kill(sprite, "fade_tween")
	sprite.show()
	sprite.modulate.a = 1.0


## `item_id` drops out of `enemy_id` with a bounce and fades.
func show_drop(enemy_id: int, item_id: String) -> void:
	if not _views.has(enemy_id) or overlay == null:
		return
	var sprite: Control = _views[enemy_id]["sprite"]
	var texture_path: String = FALLBACK_ICON
	var item: Dictionary = GameDatabase.get_item(int(item_id))
	if item.has("iconFile"):
		texture_path = "res://assets/items/" + str(item["iconFile"])
	if not ResourceLoader.exists(texture_path):
		texture_path = FALLBACK_ICON

	var icon := TextureRect.new()
	icon.texture = _texture(texture_path)
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(icon)
	icon.global_position = sprite.global_position

	var tween: Tween = create_tween()
	tween.parallel().tween_property(icon, "global_position:x", icon.global_position.x + DROP_DISTANCE.x, DROP_SECONDS)
	tween.parallel().tween_property(icon, "global_position:y", icon.global_position.y + DROP_DISTANCE.y, DROP_SECONDS) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(DROP_HOLD_SECONDS)
	tween.tween_property(icon, "modulate:a", 0.0, DROP_FADE_SECONDS)
	tween.tween_callback(icon.queue_free)


## Where `enemy_id`'s sprite is on screen (the limit crystal starts there), or null.
func sprite_position(enemy_id: int) -> Variant:
	if not _views.has(enemy_id):
		return null
	return (_views[enemy_id]["sprite"] as Control).global_position


## The wrapper's top-left inside the container: `disp_pos` mapped from DISP_REFERENCE
## into the region and centred on the wrapper; the corner when there is none.
func _wrapper_position(disp_pos: Vector2) -> Vector2:
	var region_size: Vector2 = _container.size
	if region_size.x <= 1.0 or region_size.y <= 1.0:
		region_size = size
	if region_size.x <= 1.0 or region_size.y <= 1.0:
		region_size = REGION_FALLBACK_SIZE
	if disp_pos == Vector2.ZERO:
		return Vector2.ZERO
	var nx: float = clampf(disp_pos.x / DISP_REFERENCE.x, 0.0, 1.0)
	var ny: float = clampf(disp_pos.y / DISP_REFERENCE.y, 0.0, 1.0)
	return Vector2(nx * region_size.x, ny * region_size.y) - WRAPPER_SIZE * 0.5


func _texture(path: String) -> Texture2D:
	if not _texture_cache.has(path):
		_texture_cache[path] = ResourceLoader.load(path) as Texture2D
	return _texture_cache[path]
