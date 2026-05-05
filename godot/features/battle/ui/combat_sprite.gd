extends TextureRect

# To keep track of states and the current active animation
var idle_anim: Dictionary = {}
var atk_anim: Dictionary = {}
var magic_standby_anim: Dictionary = {}
var magic_atk_anim: Dictionary = {}
var limit_atk_anim: Dictionary = {}

var is_attacking: bool = false
var is_magic_standby: bool = false
var is_magic_atk: bool = false
var is_limit_atk: bool = false
var is_enemy: bool = false
var attack_loop_count: int = 0
var max_attack_loops: int = 1
var current_frame_idx: int = 0
var current_frame_timer: float = 0.0

var party_index: int = -1

@onready var battle_manager: Node = get_node("/root/Main/BattleManager") if get_tree().root.has_node("Main/BattleManager") else null

func _ready() -> void:
	if not battle_manager:
		# Fallback if the path is not standard
		var bt = get_tree().root.find_child("BattleManager", true, false)
		if bt:
			battle_manager = bt

	if battle_manager:
		battle_manager.unit_action_started.connect(_on_unit_action_started)
		battle_manager.enemy_action_started.connect(_on_enemy_action_started)
		battle_manager.action_queued.connect(_on_action_queued)

func setup(p_index: int, template_id: String, p_is_enemy: bool = false) -> void:
	party_index = p_index
	is_enemy = p_is_enemy

	# Load animation data using TextureBuilder
	if is_enemy:
		idle_anim = TextureBuilder.load_monster_animation_data(template_id, "idle")
		atk_anim = TextureBuilder.load_monster_animation_data(template_id, "atk")
		max_attack_loops = 2
	else:
		idle_anim = TextureBuilder.load_unit_animation_data(template_id, "idle")
		atk_anim = TextureBuilder.load_unit_animation_data(template_id, "atk")
		magic_standby_anim = TextureBuilder.load_unit_animation_data(template_id, "magic_standby")
		magic_atk_anim = TextureBuilder.load_unit_animation_data(template_id, "magic_atk")
		limit_atk_anim = TextureBuilder.load_unit_animation_data(template_id, "limit_atk")
		if limit_atk_anim.is_empty():
			limit_atk_anim = TextureBuilder.load_unit_animation_data(template_id, "limit")
		max_attack_loops = 1

	# Visual fail-fast: If idle animation is missing, fallback to icon and turn neon pink
	if idle_anim.is_empty():
		if is_enemy:
			var icon_path = "res://assets/monster_icon/monster_icon_" + template_id + ".png"
			if ResourceLoader.exists(icon_path):
				texture = ResourceLoader.load(icon_path) as Texture2D
			else:
				texture = ResourceLoader.load("res://icon.svg") as Texture2D
		else:
			texture = ResourceLoader.load("res://icon.svg") as Texture2D
			modulate = Color(1, 0, 1, 1) # Neon pink
	else:
		_play_idle()

func _play_idle() -> void:
	is_attacking = false
	is_magic_standby = false
	is_magic_atk = false
	is_limit_atk = false
	current_frame_idx = 0
	current_frame_timer = 0.0

	if not idle_anim.is_empty() and idle_anim.get("frames", []).size() > 0:
		texture = idle_anim["frames"][current_frame_idx]

func _play_magic_standby() -> void:
	if magic_standby_anim.is_empty() or magic_standby_anim.get("frames", []).size() == 0:
		_play_idle()
		return

	is_attacking = false
	is_magic_standby = true
	is_limit_atk = false
	current_frame_idx = 0
	current_frame_timer = 0.0
	texture = magic_standby_anim["frames"][current_frame_idx]

func _play_magic_atk() -> void:
	if magic_atk_anim.is_empty() or magic_atk_anim.get("frames", []).size() == 0:
		_play_atk()
		return

	is_attacking = true
	is_magic_atk = true
	is_limit_atk = false
	attack_loop_count = 0
	current_frame_idx = 0
	current_frame_timer = 0.0
	texture = magic_atk_anim["frames"][current_frame_idx]

func _play_limit_atk() -> void:
	if limit_atk_anim.is_empty() or limit_atk_anim.get("frames", []).size() == 0:
		_play_atk()
		return

	is_attacking = true
	is_magic_atk = false
	is_limit_atk = true
	max_attack_loops = 1
	attack_loop_count = 0
	current_frame_idx = 0
	current_frame_timer = 0.0
	texture = limit_atk_anim["frames"][current_frame_idx]

func _play_atk() -> void:
	is_attacking = true
	is_magic_atk = false
	is_limit_atk = false
	attack_loop_count = 0
	current_frame_idx = 0
	current_frame_timer = 0.0

	# If attack animation is missing, act as if done immediately
	if atk_anim.is_empty() or atk_anim.get("frames", []).size() == 0:
		# Missing atk anim, but we still fallback gracefully without crashing
		_play_idle()
		return

	texture = atk_anim["frames"][current_frame_idx]

func _process(delta: float) -> void:
	# Convert delta (seconds) to frame delays logic? Wait, how are frame delays structured?
	# In JSON they look like: "frameDelays": [3, 3, 3, ...].
	# A frame delay of "1" is typically 1 unit. Wait, what unit? Let's check typical FFBE.
	# Typically frame delays are in 1/60th of a second (frames). We'll assume delays are *frames* at 60fps.
	# So delay time in seconds = frame_delay / 60.0

	var current_anim = idle_anim
	if is_attacking:
		if is_magic_atk:
			current_anim = magic_atk_anim
		elif is_limit_atk:
			current_anim = limit_atk_anim
		else:
			current_anim = atk_anim
	elif is_magic_standby:
		current_anim = magic_standby_anim

	if current_anim.is_empty() or current_anim.get("frames", []).size() == 0:
		return

	var frames: Array = current_anim.get("frames", [])
	var delays: Array = current_anim.get("delays", [])

	# If for some reason we exceed bounds
	if current_frame_idx >= frames.size():
		if is_attacking:
			_play_idle()
		else:
			current_frame_idx = 0
		return

	# Check delay for current frame. If delays array is shorter, default to say, 3.
	var frame_delay_val: int = 3
	if current_frame_idx < delays.size():
		frame_delay_val = delays[current_frame_idx]

	var delay_seconds: float = float(frame_delay_val) / 60.0

	current_frame_timer += delta

	if current_frame_timer >= delay_seconds:
		# Consume the delay
		current_frame_timer -= delay_seconds

		# Advance frame
		current_frame_idx += 1

		if current_frame_idx >= frames.size():
			if is_attacking:
				attack_loop_count += 1
				if attack_loop_count >= max_attack_loops:
					# Attack animation finished
					_play_idle()
				else:
					# Loop attack
					current_frame_idx = 0
					texture = frames[current_frame_idx]
			else:
				# Loop idle
				current_frame_idx = 0
				texture = frames[current_frame_idx]
		else:
			# Just update texture
			texture = frames[current_frame_idx]

func _on_unit_action_started(unit_index: int, action: int) -> void:
	if is_enemy or unit_index != party_index:
		return

	# Check if action is ATTACK
	if action == battle_manager.CombatAction.ATTACK:
		_play_atk()
	elif action == battle_manager.CombatAction.SKILL or action == battle_manager.CombatAction.ITEM:
		var queued_payload: Dictionary = battle_manager.party_data[party_index].get("queued_payload", {})
		var source_type: String = str(queued_payload.get("source_type", "skill"))
		if source_type == "limitburst":
			_play_limit_atk()
			return

		var action_id = battle_manager.party_data[party_index].get("queued_action_id", "")
		if DataManager.game_data_skills_magic.has(action_id):
			max_attack_loops = 3
			_play_magic_atk()
		else:
			_play_atk()

func _on_enemy_action_started(enemy_index: int, action: int) -> void:
	if not is_enemy or enemy_index != party_index:
		return

	if action == battle_manager.CombatAction.ATTACK:
		_play_atk()

func _on_action_queued(unit_index: int, action: int, action_id: String) -> void:
	if is_enemy or unit_index != party_index:
		return

	if action == battle_manager.CombatAction.SKILL or action == battle_manager.CombatAction.ITEM:
		if DataManager.game_data_skills_magic.has(action_id):
			_play_magic_standby()
		else:
			_play_idle()
	else:
		_play_idle()
