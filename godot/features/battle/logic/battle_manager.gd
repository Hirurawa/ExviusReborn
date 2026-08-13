extends Node

signal battle_state_ready
signal enemy_hp_changed(enemy_index: int, new_hp: int, max_hp: int, hp_percent: int)
signal turn_changed(new_turn: int)
signal unit_stats_updated(index: int, unit_name: String, cur_hp: int, max_hp: int, cur_mp: int, max_mp: int, cur_limit: int, max_limit: int)
signal attack_landed(target_team: String, target_index: int, damage: int, chain_count: int, receipt_type: String)
signal unit_acted(index: int)
signal unit_action_started(unit_index: int, action: CombatAction)
signal action_queued(unit_index: int, action: CombatAction, action_id: String)
signal enemy_action_started(enemy_index: int, action: CombatAction)
signal mission_failed

signal item_refunded(item_id: String)
signal wave_changed()
signal wave_transition_started(current_wave: int, next_wave: int, total_waves: int)
signal item_dropped(enemy_index: int, item_id: String)
signal limit_crystal_dropped(enemy_index: int, target_unit_index: int)

## In-combat story dialogue. BattleManager emits dialogue_requested with the
## ordered [{speaker, text}] lines for a wave trigger; the battle UI shows an
## overlay and calls close_dialogue() once the player has clicked through them.
signal dialogue_requested(lines: Array)
signal dialogue_completed

enum BattleState { INIT, PLAYER_TURN, RESOLVING_TURN, ENEMY_TURN, BATTLE_OVER }
enum CombatAction { ATTACK, DEFEND, SKILL, ITEM }

const ENEMY_ATTACK_DELAY_FRAMES: int = 60
## Frames left between consecutive enemy actions so a multi-action monster turn reads
## as a sequence instead of every hit landing on the same frame.
const ENEMY_ACTION_GAP_FRAMES: int = 20
## Least amount of timeline one enemy action may occupy. An action whose effects carry
## no attack frames at all -- a buff, a debuff, a self-heal -- would otherwise resolve
## and be announced within ENEMY_ACTION_GAP_FRAMES of the next one, which is too fast to
## read. Sized to roughly cover BattleUI.ACTION_FEEDBACK_DURATION so each action's label
## is legible before the next replaces it.
const ENEMY_ACTION_MIN_SPAN_FRAMES: int = 90
## What an unscripted monster does on its turn. 14153 of the 16931 monsters carry no
## `ai` rows at all, so this is the common path, not an error case.
const ENEMY_DEFAULT_ATTACKS_PER_TURN: int = 1
## HP applied to an enemy when its bestiary entry has no usable encounter HP.
const DEFAULT_ENEMY_HP: int = 1000
## Offensive/defensive stat applied to an enemy when no MONSTER_PARTS row exists
## (the bestiary carries no atk/def/mag/spr). Matches the action_processor default.
const DEFAULT_ENEMY_STAT: int = 10
## Chance (0..1) that defeating an enemy with a player attack drops a Limit Crystal
## targeted at the attacking unit. See _try_drop_limit_crystal.
const LIMIT_CRYSTAL_DROP_CHANCE: float = 0.20
const LIMIT_CRYSTAL_GAIN: int = 1

## Chain system tuning.
## A chain breaks when more than CHAIN_BREAK_FRAME_THRESHOLD frames elapse between
## hits on the same target, OR when the same unit hits the target consecutively.
const CHAIN_BREAK_FRAME_THRESHOLD: int = 20
## Maximum number of chain steps that contribute to the damage multiplier. The
## chain counter itself is uncapped and keeps incrementing for display purposes;
## only the multiplier contribution saturates here.
const MAX_CHAIN_MULTIPLIER_STEPS: int = 10
## Damage multiplier added per chain step (effective_steps * step). At
## MAX_CHAIN_MULTIPLIER_STEPS this yields a 1.0 + 10*0.3 = 4.0x final multiplier,
## and stays at 4.0x for any higher chain count.
const CHAIN_DAMAGE_STEP: float = 0.3
# Legacy aliases preserved for any external references; canonical names live on CoverSystem.
const COVER_STATE_AOE: String = CoverSystem.STATE_AOE
const COVER_STATE_ST: String = CoverSystem.STATE_ST
const COVER_STATE_MITIGATION: String = CoverSystem.STATE_MITIGATION

var action_processor
var result_processor
var current_state: BattleState = BattleState.INIT
var player_units_acted_this_turn: Array = []
var current_battle_frame: int = 0
var pending_hits: Array[Dictionary] = []
## Enemy action announcements waiting on the battle frame clock, as
## { execute_on_frame, enemy_index, action, action_name }. A monster's whole turn is
## queued in one pass, so emitting enemy_action_started as each action is queued would
## fire every announcement on the same frame: the feedback label would only ever show
## the last one, and combat_sprite would play all the attack animations at once.
## Draining them on the same clock the hits use puts each announcement where its action
## actually resolves. See _schedule_enemy_announcement.
var pending_announcements: Array[Dictionary] = []

var player_units: Array = []
var enemy_units: Array = []

## Per-enemy AI, keyed by the enemy's index in enemy_units:
## { script: MonsterAIScript, state: MonsterAIState }. Rebuilt each wave, since the
## flag banks and limited_act counters belong to one monster in one encounter.
var _enemy_ai: Dictionary = {}

var party_data: Array = []
var turn_count: int = 1

var is_transitioning: bool = false
## True while a dialogue overlay is showing -- pauses the turn engine (_process)
## so no enemy acts while the player reads. The full-screen overlay blocks input.
var _dialogue_active: bool = false
## Cutscene phases for the active mission (from GameDatabase.get_mission_cutscenes),
## slotted by after_wave. Shown as placeholders via the dialogue overlay for now.
var _cutscenes: Array = []

var current_wave: int = 1
var total_waves: int = 1
## Ordered, data-driven wave descriptors for the active mission (from
## EncounterResolver). Empty when the mission has no mapped encounter chain, in
## which case the legacy random dungeon spawner is used.
var wave_plan: Array = []
var current_mission_id: String = ""
var mission_drops: Array[String] = []
## Unit EXP earned so far this battle. Accumulated per defeated enemy from its
## MONSTER_PARTS exp value (see _accumulate_enemy_rewards) and handed to
## MissionService.request_finish_mission on victory, where every party member
## gains it. Lost on defeat, like mission_drops.
var mission_unit_exp: int = 0
## Gil earned from defeated enemies (MONSTER_PARTS gil). Escrowed like
## mission_unit_exp; MissionService adds it to the mission's own gil reward.
var mission_gil: int = 0
var used_items: Dictionary = {}
var challenge_results: Array[bool] = []

var active_challenges: Array[ChallengeTracker] = []

func _ready() -> void:
	# Processors are stateless logic; instantiate as RefCounted (no add_child).
	# Keeping them out of the scene tree avoids needless per-frame iteration.
	action_processor = preload("res://features/battle/logic/action_processor.gd").new()
	result_processor = preload("res://features/battle/logic/result_processor.gd").new()

func _process(_delta: float) -> void:
	if _dialogue_active:
		return
	if current_state != BattleState.PLAYER_TURN and current_state != BattleState.ENEMY_TURN:
		return

	current_battle_frame += 1

	# Drained before the hits so an action's label and animation are already on screen
	# when its damage lands on the same frame.
	_drain_pending_announcements()

	for i in range(pending_hits.size() - 1, -1, -1):
		var hit: Dictionary = pending_hits[i]
		if hit.get("execute_on_frame", 0) <= current_battle_frame:
			var target_team: String = hit.get("target_team", "enemy")
			var target_index: int = hit.get("target_index", 0)
			var damage: int = hit.get("amount", 0)
			var attacker_team: String = hit.get("attacker_team", "player")
			var attacker_index: int = hit.get("attacker_index", 0)

			var target_array = enemy_units if target_team == "enemy" else party_data
			var final_damage: int = damage
			var chain_count_emitted: int = 0

			if target_index >= 0 and target_index < target_array.size():
				var target = target_array[target_index]
				if not target.is_empty():
					var frame_gap = current_battle_frame - target.get("last_hit_frame", -100)
					var current_attacker = attacker_index
					var base_damage = damage

					# Check for Chain Break
					if frame_gap > CHAIN_BREAK_FRAME_THRESHOLD or current_attacker == target.get("last_attacker_index", -1):
						target["chain_count"] = 0
					# Check for Chain Build (counter is unbounded; multiplier saturates below).
					elif frame_gap <= CHAIN_BREAK_FRAME_THRESHOLD and current_attacker != target.get("last_attacker_index", -1):
						target["chain_count"] += 1

					var effective_steps: int = min(target["chain_count"], MAX_CHAIN_MULTIPLIER_STEPS)
					var chain_multiplier = 1.0 + (effective_steps * CHAIN_DAMAGE_STEP)
					final_damage = int(base_damage * chain_multiplier)

					if str(hit.get("type", "")).to_lower() == "damage":
						final_damage = CoverSystem.apply_active_cover_mitigation(target, final_damage)

					# Update the hit amount before passing it to the ResultProcessor
					hit["amount"] = final_damage

					target["last_hit_frame"] = current_battle_frame
					target["last_attacker_index"] = current_attacker
					chain_count_emitted = target["chain_count"]

					var previous_hp = target.get("current_hp", 0)

					# Hand hit receipt and target to result_processor
					result_processor.apply_receipt(hit, target)

					# Enemies can drop limit crystals when hit by player attacks.
					if target_team == "enemy":
						_try_drop_limit_crystal(target_index, attacker_team, hit, final_damage)
						BattleEvents.enemy_damaged.emit(target["id"], hit)
						# If this hit killed them, roll for drops!
						if previous_hp > 0 and target["current_hp"] == 0:
							_roll_enemy_drops(target, target_index)
							_accumulate_enemy_rewards(target)
							PlayerProfile.record_monster_kill(str(target["id"]))
							BattleEvents.enemy_defeated.emit(target["id"], hit)

						set_enemy_hp(target_index, target["current_hp"])
					else:
						if previous_hp > 0 and target["current_hp"] == 0:
							BattleEvents.ally_defeated.emit()
						# For UI stats, we still need the original party_data index
						# For now, search it by instance_id or let request_unit_stats find it
						var p_idx = target.get("index", -1)
						if p_idx != -1:
							request_unit_stats(p_idx)

			attack_landed.emit(target_team, target_index, final_damage, chain_count_emitted, hit.get("type", ""))
			pending_hits.remove_at(i)

	_check_turn_progression()

func _get_living_player_party_indices() -> Array[int]:
	var living_indices: Array[int] = []
	for i in range(party_data.size()):
		var unit_data: Dictionary = party_data[i]
		if unit_data.is_empty():
			continue
		if int(unit_data.get("current_hp", 0)) > 0:
			living_indices.append(i)
	return living_indices

func _grant_limit_to_unit(unit_index: int, amount: int) -> void:
	if unit_index < 0 or unit_index >= party_data.size():
		return

	var unit_data: Dictionary = party_data[unit_index]
	if unit_data.is_empty():
		return

	var current_limit: int = int(unit_data.get("limit_gauge", 0))
	var max_limit: int = int(unit_data.get("max_limit", 0))
	if max_limit <= 0:
		return

	var next_limit: int = clampi(current_limit + amount, 0, max_limit)
	if next_limit == current_limit:
		return

	unit_data["limit_gauge"] = next_limit
	request_unit_stats(unit_index)

func _try_drop_limit_crystal(enemy_index: int, attacker_team: String, hit: Dictionary, final_damage: int) -> void:
	if attacker_team != "player":
		return
	if final_damage <= 0:
		return
	if str(hit.get("type", "")) != "DAMAGE":
		return
	if enemy_index < 0 or enemy_index >= enemy_units.size():
		return
	if randf() > LIMIT_CRYSTAL_DROP_CHANCE:
		return

	var eligible_units: Array[int] = _get_living_player_party_indices()
	if eligible_units.is_empty():
		return

	var random_target_slot: int = randi() % eligible_units.size()
	var target_unit_index: int = eligible_units[random_target_slot]
	_grant_limit_to_unit(target_unit_index, LIMIT_CRYSTAL_GAIN)
	limit_crystal_dropped.emit(enemy_index, target_unit_index)

## Entry point for a new battle. Loads mission data, builds the party / first wave,
## resets per-battle state, then emits battle_state_ready and starts the player turn.
func initialize_battle(mission_id: String) -> void:
	
	current_mission_id = mission_id
	var mission_data = MissionService.get_mission_data(str(current_mission_id))

	# Resolve the data-driven wave plan (MISSION_PHASE / scenario battles). When a
	# mission has no mapped plan, fall back to the legacy wave_count + random spawn.
	wave_plan = EncounterResolver.build_wave_plan(str(current_mission_id))
	if wave_plan.size() > 0:
		total_waves = wave_plan.size()
	else:
		total_waves = mission_data.get("wave_count", 1)
	# Cutscene phases for this mission, slotted by after_wave (see get_mission_cutscenes).
	_cutscenes = GameDatabase.get_mission_cutscenes(str(current_mission_id))
	current_wave = 1
	mission_drops.clear()
	mission_unit_exp = 0
	mission_gil = 0
	used_items.clear()
	var mission_challenges: Variant = mission_data.get("challenges", [])
	var challenge_count: int = mission_challenges.size() if mission_challenges is Array else 0
	challenge_results.resize(challenge_count)
	challenge_results.fill(false)

	initialize_challenges(mission_challenges)

	party_data = []

	if PartyService.parties.size() > 0:
		var active_party: Dictionary = PartyService.get_active_party()
		var party_instance_ids: Array = []
		if not active_party.is_empty():
			party_instance_ids = active_party.get("units", [])
		else:
			var fallback_party: Variant = PartyService.parties[0]
			if typeof(fallback_party) == TYPE_DICTIONARY:
				party_instance_ids = fallback_party.get("units", [])
			elif typeof(fallback_party) == TYPE_ARRAY:
				party_instance_ids = fallback_party

		for instance_id in party_instance_ids:
			if instance_id == "":
				party_data.append({})
				continue

			var owned_unit = null
			for u in UnitService.owned_units_ids:
				if typeof(u) == TYPE_DICTIONARY and u.get("instance_id") == instance_id:
					owned_unit = u
					break

			if owned_unit != null:
				var battle_unit = owned_unit.duplicate()

				# Use StatCalculator to get accurate max HP and MP. Compute once and
				# store on battle_unit["final_stats"] so all consumers (battle UI, skill
				# menu, action processor) read from a single source of truth.
				battle_unit["final_stats"] = StatCalculator.calculate_final_stats(battle_unit)
				var final_stats: Dictionary = battle_unit["final_stats"].get("stats", {})

				var max_hp = final_stats.get("HP", 100)
				var max_mp = final_stats.get("MP", 10)

				battle_unit["max_hp"] = max_hp
				battle_unit["current_hp"] = max_hp
				battle_unit["max_mp"] = max_mp
				battle_unit["current_mp"] = max_mp
				var limitburst_id: String = str(battle_unit.get("limitBurstId", ""))
				battle_unit["limitburst_id"] = limitburst_id
				var max_limit_gauge: int = SkillResolver.get_limitburst_max_gauge(limitburst_id)
				battle_unit["limit_gauge"] = 0
				battle_unit["max_limit"] = max_limit_gauge
				_reset_unit_queued_action(battle_unit)

				battle_unit["chain_count"] = 0
				battle_unit["last_hit_frame"] = -100
				battle_unit["last_attacker_index"] = -1

				battle_unit["team"] = "player"
				battle_unit["index"] = party_data.size()

				party_data.append(battle_unit)
			else:
				party_data.append({})

	player_units.clear()
	for unit in party_data:
		if not unit.is_empty():
			player_units.append(unit)

	# Load enemy data for the first wave.
	_spawn_wave(1, mission_data)

	current_state = BattleState.PLAYER_TURN
	player_units_acted_this_turn.clear()
	current_battle_frame = 0
	pending_hits.clear()
	pending_announcements.clear()

	turn_count = 1
	is_transitioning = false
	battle_state_ready.emit()

	# Intro cutscenes (placeholder), then the first wave's intro dialogue.
	await _play_cutscenes_for_slot(0)
	await play_dialogue(wave_dialogue_lines(1, 1))

func initialize_challenges(mission_challenge_data: Array):
	for data in mission_challenge_data:
		active_challenges.append(ChallengeFactory.create(data.parameter))

func set_enemy_hp(enemy_index: int, new_hp: int) -> void:
	if enemy_index < 0 or enemy_index >= enemy_units.size():
		return

	var enemy = enemy_units[enemy_index]
	enemy["current_hp"] = new_hp
	var max_hp = enemy.get("max_hp", enemy.get("hp", 1000))
	var pct: int = 0
	if max_hp > 0:
		pct = int((float(enemy["current_hp"]) / float(max_hp)) * 100.0)
	enemy_hp_changed.emit(enemy_index, enemy["current_hp"], max_hp, pct)

# Clears all per-turn queued action state on a unit dict in place.
# Used by battle init, end-of-turn (PLAYER->ENEMY->PLAYER), and wave transitions.
func _reset_unit_queued_action(unit: Dictionary) -> void:
	unit["queued_action"] = CombatAction.ATTACK
	unit["queued_action_name"] = ""
	unit["queued_action_id"] = ""
	unit.erase("queued_payload")
	# Reset target so stale per-skill targets (e.g. self-targeting) don't bleed into the next basic attack.
	unit["queued_target_team"] = "enemy"
	unit["queued_target_index"] = 0
	unit["is_defending"] = false

## Records a unit's intent for the upcoming resolve. Called both from drag gestures
## (ATTACK/DEFEND) and from menu confirms (SKILL/ITEM with action_id + payload).
func set_queued_action(unit_index: int, new_action: CombatAction, action_name: String = "", action_id: String = "", payload: Dictionary = {}) -> void:
	if unit_index < 0 or unit_index >= party_data.size():
		return
	var unit_data: Dictionary = party_data[unit_index]
	if unit_data.is_empty():
		return
		
	var old_payload = unit_data.get("queued_payload", {})
	if old_payload.get("is_item", false) == true:
		item_refunded.emit(old_payload.get("original_item_id"))
		
	unit_data["queued_action"] = new_action
	unit_data["queued_action_name"] = action_name
	unit_data["queued_action_id"] = action_id
	unit_data["queued_payload"] = payload

	action_queued.emit(unit_index, new_action, action_id)

func _resolve_queued_action_data(action_id: String, payload: Dictionary) -> Dictionary:
	var resolved_action_data: Dictionary = payload.get("resolved_action_data", {})
	if not resolved_action_data.is_empty():
		return {
			"resolved_action_id": str(payload.get("resolved_action_id", action_id)),
			"resolved_action_data": resolved_action_data,
			"parsed_data": payload.get("parsed_data", {})
		}

	var resolved_action_id: String = str(payload.get("resolved_action_id", action_id))
	return SkillResolver.resolve_combat_skill(resolved_action_id)

func _extract_skill_mp_cost(skill_data: Dictionary) -> int:
	var cost_value: Variant = skill_data.get("cost", {})
	if cost_value is Dictionary:
		var cost_dict: Dictionary = cost_value
		if cost_dict.has("MP"):
			return maxi(0, int(cost_dict.get("MP", 0)))
	elif typeof(cost_value) in [TYPE_INT, TYPE_FLOAT]:
		return maxi(0, int(cost_value))
	for key in ["mp_cost", "mpCost", "costMp"]:
		if skill_data.has(key):
			return maxi(0, int(skill_data.get(key, 0)))
	return 0

func _try_spend_skill_mp(unit_index: int, unit_data: Dictionary, payload_data: Dictionary, skill_data: Dictionary) -> bool:
	if unit_data.is_empty():
		return false

	var source_type: String = str(payload_data.get("source_type", "skill"))
	if source_type == "limitburst":
		unit_data["limit_gauge"] = 0
		request_unit_stats(unit_index)
		return true

	var mp_cost: int = _extract_skill_mp_cost(skill_data)
	if mp_cost <= 0:
		return true

	var current_mp: int = int(unit_data.get("current_mp", 0))
	if current_mp < mp_cost:
		return false

	unit_data["current_mp"] = maxi(0, current_mp - mp_cost)
	request_unit_stats(unit_index)
	return true

func execute_queued_action(attacker_index: int) -> void:
	if current_state != BattleState.PLAYER_TURN:
		return
	if attacker_index in player_units_acted_this_turn:
		return

	player_units_acted_this_turn.append(attacker_index)
	var attacker_data: Dictionary = party_data[attacker_index] if attacker_index < party_data.size() else {}
	if attacker_data.is_empty(): return
	var action: int = attacker_data.get("queued_action", CombatAction.ATTACK)

	# Snapshot the executed action so the reload button can re-queue it on later turns.
	attacker_data["last_action"] = action
	attacker_data["last_action_name"] = attacker_data.get("queued_action_name", "")
	attacker_data["last_action_id"] = attacker_data.get("queued_action_id", "")
	var _last_payload_src: Dictionary = attacker_data.get("queued_payload", {})
	attacker_data["last_payload"] = _last_payload_src.duplicate(true)
	attacker_data["last_target_team"] = attacker_data.get("queued_target_team", "enemy")
	attacker_data["last_target_index"] = attacker_data.get("queued_target_index", 0)

	unit_acted.emit(attacker_index)

	if action == CombatAction.DEFEND:
		attacker_data["is_defending"] = true
		attacker_data["challenge_kill_method"] = ""
		_check_turn_progression()
		return
	elif action == CombatAction.SKILL or action == CombatAction.ITEM:
		var action_name: String = attacker_data.get("queued_action_name", "")
		var action_id: String = attacker_data.get("queued_action_id", "")
		var payload_data: Dictionary = attacker_data.get("queued_payload", {})
		if OS.is_debug_build():
			print("Executing: ", action_name)

		unit_action_started.emit(attacker_index, action)

		if action == CombatAction.ITEM:
			var item_id: String = payload_data.get("original_item_id", "")
			if item_id != "":
				used_items[item_id] = used_items.get(item_id, 0) + 1
				BattleEvents.item_used.emit(item_id)

		var resolved_action: Dictionary = _resolve_queued_action_data(action_id, payload_data)
		var target_skill_data: Dictionary = resolved_action.get("resolved_action_data", {}) if not resolved_action.is_empty() else {}

		if target_skill_data.is_empty():
			push_error("Error: Skill/Item Ability not found in database: " + action_name)
			return

		if action == CombatAction.SKILL:
			if not _try_spend_skill_mp(attacker_index, attacker_data, payload_data, target_skill_data):
				push_warning("BattleManager: Not enough MP to execute skill: %s" % action_name)
				_check_turn_progression()
				return

		var parsed_data: Dictionary = payload_data.get("parsed_data", {})
		if parsed_data.is_empty():
			parsed_data = resolved_action.get("parsed_data", {}) if not resolved_action.is_empty() else {}
		if parsed_data.is_empty():
			parsed_data = SkillResolver.parse_skill_effects(target_skill_data)
		if OS.is_debug_build():
			print("Parsed Skill/Item: ", parsed_data)
		
		# queued_target_index is always a party_data index (stable slot reference)
		var target_team: String = attacker_data.get("queued_target_team", "enemy")
		var target_idx: int = attacker_data.get("queued_target_index", 0)

		var primary_target: Dictionary = {}
		if target_team == "enemy":
			if target_idx < 0 or target_idx >= enemy_units.size(): target_idx = 0
			if enemy_units.size() > 0: primary_target = enemy_units[target_idx]
		else:
			# Ally targets store party_data indices; player_units is a compact subset whose positions differ when slots are empty
			if target_idx < 0 or target_idx >= party_data.size(): target_idx = 0
			if party_data.size() > 0: primary_target = party_data[target_idx]

		if attacker_data.get("queued_payload").get("source_type") == "ability":
			BattleEvents.ability_used.emit(attacker_data.get("queued_payload"))
		elif attacker_data.get("queued_payload").get("source_type") == "magic":
			BattleEvents.magic_used.emit(attacker_data.get("queued_payload"))
			
		# Route the skill to the execution pipeline
		execute_parsed_skill(parsed_data, attacker_data, primary_target)

		_check_turn_progression()
		return
	elif action == CombatAction.ATTACK:
		# Keep accepting inputs for other units by not changing state here
		unit_action_started.emit(attacker_index, CombatAction.ATTACK)
		attacker_data["challenge_kill_method"] = ""
		
		# Build a dummy effect so it goes through our standard pipeline
		var dummy_effect = {
			"type": "PHYSICAL_DAMAGE",
			"modifier": 1.0,
			"target_area": 1,
			"target_type": 1
		}
		
		# Retrieve the actual queued target index
		var target_index: int = attacker_data.get("queued_target_index", 0)
		var target_team: String = attacker_data.get("queued_target_team", "enemy")
		
		var attack_frames: Array[int] = []
		var attack_damage: Array[int] = []
		# 1. Split the main string by the hyphen
		var frame_segments: PackedStringArray = attacker_data.get("attackFrames").split("-")

		# 2. Loop through each segment
		for segment in frame_segments:
			# 3. Split by colon to isolate the first number
			var parts: PackedStringArray = segment.split(":")
			
			# 4. Convert the first part to an integer and add to array
			attack_frames.append(parts[0].to_int())
			attack_damage.append(parts[1].to_int())
		
		var target_data: Dictionary = {}
		if target_team == "enemy":
			if target_index < 0 or target_index >= enemy_units.size(): target_index = 0
			if enemy_units.size() > 0: target_data = enemy_units[target_index]
		else:
			# Ally targets store party_data indices; player_units is a compact subset whose positions differ when slots are empty
			if target_index < 0 or target_index >= party_data.size(): target_index = 0
			if party_data.size() > 0: target_data = party_data[target_index]

		if target_data.is_empty():
			push_warning("execute_queued_action: ATTACK has no valid target (team=%s idx=%d)" % [target_team, target_index])
			_check_turn_progression()
			return

		# Insert attack frames/damage directly into the dummy effect so standard processing can read them
		dummy_effect["attack_frames"] = attack_frames
		dummy_effect["attack_damage"] = attack_damage
		_queue_effect_hits(dummy_effect, attacker_data, target_data)

func _check_turn_progression() -> void:
	# Announcements are part of the turn playing out: ending it while a monster still has
	# actions left to announce would hand control back to the player mid-sequence.
	if not pending_hits.is_empty() or not pending_announcements.is_empty():
		return

	check_battle_state()

	# If the battle just ended (wave clear / defeat), check_battle_state() has
	# started an async transition. Bail out so we don't fire an enemy turn against
	# a dead wave (which caused the "last dead enemy attacks back" bug).
	if is_transitioning:
		return

	if current_state == BattleState.PLAYER_TURN:
		var all_acted: bool = true

		for i in range(player_units.size()):
			var unit: Dictionary = player_units[i]
			# A living unit is not empty, has current_hp, and current_hp > 0
			if not unit.is_empty() and unit.has("current_hp") and unit.get("current_hp") > 0:
				# Find the original party index since player_units_acted_this_turn tracks UI party indices
				var p_idx = unit.get("index", -1)
				if p_idx != -1 and p_idx not in player_units_acted_this_turn:
					all_acted = false
					break

		if all_acted:
			current_state = BattleState.ENEMY_TURN
			_execute_enemy_turn()
	elif current_state == BattleState.ENEMY_TURN:
		_on_turn_end("enemy")
		_tick_active_effect_durations(party_data)
		_tick_active_effect_durations(enemy_units)
		# Transition back to PLAYER_TURN
		player_units_acted_this_turn.clear()
		current_battle_frame = 0  # Avoid unbounded growth and stale chain timing across turns.
		for unit in player_units:
			if not unit.is_empty():
				_reset_unit_queued_action(unit)

		turn_count += 1
		turn_changed.emit(turn_count)
		current_state = BattleState.PLAYER_TURN

func _tick_active_effect_durations(units: Array) -> void:
	for unit in units:
		if unit.is_empty():
			continue
		if not unit.has("active_effects"):
			continue

		var active_effects: Array = unit.get("active_effects", [])
		if active_effects.is_empty():
			continue

		var remaining_effects: Array = []
		for effect in active_effects:
			if typeof(effect) != TYPE_DICTIONARY:
				continue

			var next_duration: int = int(effect.get("duration", 0)) - 1
			if next_duration > 0:
				var updated_effect: Dictionary = effect.duplicate(true)
				updated_effect["duration"] = next_duration
				remaining_effects.append(updated_effect)

		unit["active_effects"] = remaining_effects
		unit["final_stats"] = StatCalculator.calculate_final_stats(unit)

## Runs every living enemy's turn. Scripted monsters (2778 of them) are driven by
## MonsterAIRuntime, which can produce several actions per monster; the rest fall back
## to one basic attack. Actions are queued into pending_hits staggered along the frame
## timeline so a multi-action turn plays out in sequence rather than all at once.
func _execute_enemy_turn() -> void:
	if _get_living_units(player_units).is_empty():
		return

	var frame_cursor: int = 0
	for enemy_index in range(enemy_units.size()):
		var enemy: Dictionary = enemy_units[enemy_index]
		if enemy.is_empty() or int(enemy.get("current_hp", 0)) <= 0:
			continue
		# The party can be wiped partway through the enemy turn.
		if _get_living_units(player_units).is_empty():
			break
		frame_cursor += _run_enemy_turn(enemy_index, frame_cursor)


## Queues one enemy's whole turn starting at `frame_cursor`, returning how many frames
## of timeline it consumed.
func _run_enemy_turn(enemy_index: int, frame_cursor: int) -> int:
	var enemy: Dictionary = enemy_units[enemy_index]
	var ai: Dictionary = _enemy_ai_for(enemy_index)
	var ai_script: MonsterAIScript = ai.get("script")
	var state: MonsterAIState = ai.get("state")

	if ai_script == null or not ai_script.has_script():
		var span: int = 0
		for _i in range(ENEMY_DEFAULT_ATTACKS_PER_TURN):
			span += _action_timeline_span(_queue_enemy_basic_attack(enemy_index, frame_cursor + span))
		return span

	var actions: Array[Dictionary] = MonsterAIRuntime.run_turn(ai_script, state, _build_enemy_ai_context(enemy_index))
	if OS.is_debug_build():
		print("[AI] %s (#%d) turn %d: %d action(s)  %s" % [
			str(enemy.get("name", "?")), enemy_index, turn_count, actions.size(), state.describe(),
		])

	var consumed: int = 0
	for action in actions:
		consumed += _action_timeline_span(_queue_enemy_action(enemy_index, action, frame_cursor + consumed))
	return consumed


## How much timeline one enemy action occupies: its own hit span plus a beat, but never
## less than ENEMY_ACTION_MIN_SPAN_FRAMES. A `wait` or `turn_end` reports a span of 0 and
## takes no timeline at all -- it produces nothing to see, so pausing on it would just
## look like the game had hung.
func _action_timeline_span(hit_span: int) -> int:
	if hit_span <= 0:
		return 0
	return maxi(hit_span + ENEMY_ACTION_GAP_FRAMES, ENEMY_ACTION_MIN_SPAN_FRAMES)



## Queues a single MonsterAIRuntime action, returning the frames it spans. `wait` and
## `guard` occupy a slot without producing hits, and an unresolvable skill degrades to
## a basic attack rather than silently doing nothing.
func _queue_enemy_action(enemy_index: int, action: Dictionary, frame_offset: int) -> int:
	var kind: String = str(action.get("kind", ""))

	if kind == MonsterAIRuntime.KIND_WAIT or kind == MonsterAIRuntime.KIND_GUARD:
		if kind == MonsterAIRuntime.KIND_GUARD:
			enemy_units[enemy_index]["is_defending"] = true
		return 0

	if kind == MonsterAIRuntime.KIND_SKILL:
		var skill_id: String = str(action.get("skill_id", ""))
		print(GameDatabase.get_monster_skill(skill_id).get("name"))
		if skill_id != "":
			var span: int = _queue_enemy_skill(enemy_index, skill_id, action, frame_offset)
			if span >= 0:
				return span
		# No usable skill: the rule named an index outside this monster's skill set, or
		# every opcode in it is one skill_schema.json does not cover.
		return _queue_enemy_basic_attack(enemy_index, frame_offset)

	return _queue_enemy_basic_attack(enemy_index, frame_offset)


## Queues a monster skill through the shared opcode pipeline. Returns the frames it
## spans, or -1 when the skill decoded to nothing executable so the caller can fall
## back. Primary targets are chosen per effect, because one skill can mix
## player-targeting and self/ally-targeting effects and TargetResolver trusts the
## primary target it is handed.
func _queue_enemy_skill(enemy_index: int, skill_id: String, action: Dictionary, frame_offset: int) -> int:
	var record: Dictionary = GameDatabase.get_monster_skill_record(skill_id)
	if record.is_empty():
		return -1
	var parsed: Dictionary = SkillResolver.parse_skill_effects(record)
	var effects: Array = parsed.get("effects", [])
	if effects.is_empty():
		return -1

	var caster: Dictionary = enemy_units[enemy_index]

	var span: int = 0
	var queued: int = 0
	for effect in effects:
		effect["element"] = parsed.get("element_inflict")
		var primary: Dictionary = _pick_enemy_target(caster, int(effect.get("target_type", 1)), action)
		if primary.is_empty():
			continue
		_queue_effect_hits(effect, caster, primary, frame_offset)
		span = maxi(span, _effect_span(effect))
		queued += 1

	if queued == 0:
		return -1

# Announced only once we know the skill actually landed something -- otherwise the
	# caller's fallback to a basic attack would announce a second time and the UI would
	# flash the skill name before replacing it.
	_schedule_enemy_announcement(enemy_index, CombatAction.SKILL, str(record.get("name", "")), frame_offset)
	return maxi(span, ENEMY_ATTACK_DELAY_FRAMES)


## Queues the plain physical attack, timed off the monster's attack animation. This is
## the path unscripted monsters and `attack` rules both take.
func _queue_enemy_basic_attack(enemy_index: int, frame_offset: int) -> int:
	var caster: Dictionary = enemy_units[enemy_index]
	var target: Dictionary = _pick_enemy_target(caster, 1, {})
	if target.is_empty():
		return 0

	# An empty name so a skill name from an earlier action this turn cannot leak into
	# the feedback for a plain attack.
	_schedule_enemy_announcement(enemy_index, CombatAction.ATTACK, "", frame_offset)
	var delay: int = _enemy_attack_delay_frames(str(caster.get("id", "")))
	_queue_effect_hits({
		"type": "PHYSICAL_DAMAGE",
		"modifier": 1.0,
		"target_area": 1,
		"target_type": 1,
		"attack_frames": [delay],
		"attack_damage": [[100]],
	}, caster, target, frame_offset)
	return delay


## How long the monster's attack animation runs, in frames (played twice, matching the
## original hand-rolled enemy attack). Falls back to ENEMY_ATTACK_DELAY_FRAMES.
func _enemy_attack_delay_frames(monster_id: String) -> int:
	var anim_data: Dictionary = TextureBuilder.load_monster_animation_data(monster_id, "atk")
	if anim_data.is_empty():
		return ENEMY_ATTACK_DELAY_FRAMES
	var total_frames: int = 0
	for d in anim_data.get("delays", []):
		total_frames += int(d)
	return total_frames * 2 if total_frames > 0 else ENEMY_ATTACK_DELAY_FRAMES

## Queues an enemy action announcement for the frame its action starts on, instead of
## emitting now. `action_name` is carried here rather than added to the signal, so the
## signal's other listener (combat_sprite) is unaffected; the drain writes it onto the
## enemy dict just before emitting, which is where BattleUI reads it from.
func _schedule_enemy_announcement(enemy_index: int, action: CombatAction, action_name: String, frame_offset: int) -> void:
	pending_announcements.append({
		"execute_on_frame": current_battle_frame + frame_offset,
		"enemy_index": enemy_index,
		"action": action,
		"action_name": action_name,
	})


## Emits every scheduled announcement whose frame has arrived, oldest first so a
## monster's actions are announced in the order it chose them.
func _drain_pending_announcements() -> void:
	if pending_announcements.is_empty():
		return

	var still_pending: Array[Dictionary] = []
	for announcement in pending_announcements:
		if int(announcement.get("execute_on_frame", 0)) > current_battle_frame:
			still_pending.append(announcement)
			continue

		var enemy_index: int = int(announcement.get("enemy_index", -1))
		if enemy_index < 0 or enemy_index >= enemy_units.size():
			continue
		var enemy: Dictionary = enemy_units[enemy_index]
		if enemy.is_empty():
			continue
		enemy["current_action_name"] = str(announcement.get("action_name", ""))
		enemy_action_started.emit(enemy_index, announcement.get("action", CombatAction.ATTACK))

	pending_announcements = still_pending


## The last frame an effect's hits land on, used to space consecutive actions.
func _effect_span(effect: Dictionary) -> int:
	var span: int = 0
	for frame in effect.get("attack_frames", []):
		span = maxi(span, int(frame))
	return span


## The compiled script + live state for an enemy, built on first use this wave. Keyed on
## the 9-digit instance_id, which is what the `ai` table keys on -- the base `id` is the
## shared monster and would hand a boss its trash-mob variant's behaviour.
func _enemy_ai_for(enemy_index: int) -> Dictionary:
	if _enemy_ai.has(enemy_index):
		return _enemy_ai[enemy_index]
	var enemy: Dictionary = enemy_units[enemy_index]
	var monster_id: String = str(enemy.get("instance_id", enemy.get("id", "")))
	var entry: Dictionary = {
		"script": MonsterAIScript.compile(monster_id),
		"state": MonsterAIState.new(monster_id),
	}
	_enemy_ai[enemy_index] = entry
	return entry


## The battle-state view MonsterAIRuntime evaluates conditions against. `party` is
## party_data, not player_units, so the AI's 1-based party slots line up with the UI's
## stable slots (player_units is a compact subset that shifts when a slot is empty).
func _build_enemy_ai_context(enemy_index: int) -> Dictionary:
	var by_id: Dictionary = {}
	for other in enemy_units:
		if not other.is_empty():
			by_id[str(other.get("instance_id", other.get("id", "")))] = other
	return {
		"self": enemy_units[enemy_index],
		"party": party_data,
		"enemies": enemy_units,
		"monsters_by_id": by_id,
	}


## targetSelect stat modes -> [final_stats key, pick the maximum?]. In the datamine's
## vocabulary `int` is MAG and `mind` is SPR.
const _TARGET_STAT_MODES: Dictionary = {
	"atk_max": ["ATK", true], "atk_min": ["ATK", false],
	"def_max": ["DEF", true], "def_min": ["DEF", false],
	"int_max": ["MAG", true], "int_min": ["MAG", false],
	"mind_max": ["SPR", true], "mind_min": ["SPR", false],
}
## targetSelect modes that compare a live pool value instead of a base stat.
const _TARGET_LIVE_MODES: Dictionary = {
	"hp_max": ["current_hp", true], "hp_min": ["current_hp", false],
	"mp_max": ["current_mp", true], "mp_min": ["current_mp", false],
}


## The primary target for one enemy effect. `target_type` is the effect's own
## (1 = the player party, 2/6 = the monster's own side, 3 = itself); the AI rule's
## targetSelect mode then picks which party member. {} when there is nobody to hit.
func _pick_enemy_target(caster: Dictionary, target_type: int, action: Dictionary) -> Dictionary:
	if target_type == 3:
		return caster
	if target_type == 2 or target_type == 6:
		var allies: Array[Dictionary] = _get_living_units(enemy_units)
		return allies[randi() % allies.size()] if not allies.is_empty() else caster

	var living: Array[Dictionary] = _get_living_units(player_units)
	if living.is_empty():
		return {}
	return _select_by_target_mode(
		living,
		str(action.get("target_mode", "random")),
		int(action.get("target_param", 0))
	)


## Applies an AI rule's targetSelect mode to a pool of living units. 48089 of the
## table's 49944 rules just say "random"; the rest aim at a stat extreme or a fixed
## party slot. Modes we do not model (the ~60 rows keying off buffs, statuses or
## revenge counters) fall back to random rather than dropping the action.
func _select_by_target_mode(pool: Array[Dictionary], mode: String, param: int) -> Dictionary:
	if mode == "disp_order":
		for unit in pool:
			if int(unit.get("index", -1)) == param:
				return unit
	elif _TARGET_LIVE_MODES.has(mode):
		var live: Array = _TARGET_LIVE_MODES[mode]
		return _pick_extreme(pool, str(live[0]), bool(live[1]), false)
	elif _TARGET_STAT_MODES.has(mode):
		var stat: Array = _TARGET_STAT_MODES[mode]
		return _pick_extreme(pool, str(stat[0]), bool(stat[1]), true)
	return pool[randi() % pool.size()]


## The pool member with the highest (or lowest) value of `key`, read either from the
## unit dict directly or from its final_stats block.
func _pick_extreme(pool: Array[Dictionary], key: String, want_max: bool, from_stats: bool) -> Dictionary:
	var best: Dictionary = pool[0]
	var best_value: int = _target_metric(best, key, from_stats)
	for unit in pool:
		var value: int = _target_metric(unit, key, from_stats)
		if value > best_value if want_max else value < best_value:
			best = unit
			best_value = value
	return best


func _target_metric(unit: Dictionary, key: String, from_stats: bool) -> int:
	if not from_stats:
		return int(unit.get(key, 0))
	var stats: Dictionary = unit.get("final_stats", {}).get("stats", {})
	return int(stats.get(key, 0))

## Re-emits unit_stats_updated for the given party slot so UI can pull fresh values
## without holding a direct reference to party_data.
func request_unit_stats(index: int) -> void:
	if index < 0 or index >= party_data.size():
		return

	var unit_data: Dictionary = party_data[index]
	if unit_data.is_empty():
		return

	var unit_name: String = unit_data.get("unitName", "ERR_MISSING_NAME")
	var cur_hp: int = unit_data.get("current_hp", 0)
	var max_hp: int = unit_data.get("max_hp", 1)
	var cur_mp: int = unit_data.get("current_mp", 0)
	var max_mp: int = unit_data.get("max_mp", 1)
	var cur_limit: int = unit_data.get("limit_gauge", 0)
	var max_limit: int = unit_data.get("max_limit", 100)

	unit_stats_updated.emit(index, unit_name, cur_hp, max_hp, cur_mp, max_mp, cur_limit, max_limit)

func _are_all_units_dead(team: Array) -> bool:
	if team.size() == 0:
		return true # Prevent edge cases where an empty wave triggers a soft-lock

	for unit in team:
		if unit.get("current_hp", 0) > 0:
			return false

	return true

# === Story dialogue ===

## Ordered [{speaker, text}] lines for a wave's trigger (cond 1 = on start,
## 2 = on victory), or [] when the wave has no script, that trigger has no
## lines, or the first-time gate switch is already set for the player (seen).
func wave_dialogue_lines(wave_index: int, cond: int) -> Array:
	if wave_index < 1 or wave_index > wave_plan.size():
		return []
	var wave: Dictionary = wave_plan[wave_index - 1]
	var script_id: String = str(wave.get("battle_script_id", ""))
	if script_id == "" or script_id == "0":
		return []
	if _dialogue_gate_seen(wave.get("switch_non_info")):
		return []
	var lines: Array = []
	for seg in MissionTimeline.parse_battle_script(script_id):
		if int(seg.get("cond", 0)) == cond:
			for ln in seg.get("lines", []):
				lines.append(ln)
	return lines

## True when the phase's first-time gate switch is already unlocked -- i.e. the
## player has seen this dialogue (the switch is set when the mission is cleared).
func _dialogue_gate_seen(gate: Variant) -> bool:
	if gate == null:
		return false
	var s: String = str(gate).strip_edges()
	if s == "" or s == "0" or s == "null":
		return false
	return SwitchService.is_unlocked(gate)

## Show the given lines and pause the battle until the player clicks through.
## No-op for empty lines. The overlay (battle_ui) drives close_dialogue().
func play_dialogue(lines: Array) -> void:
	if lines.is_empty():
		return
	_dialogue_active = true
	dialogue_requested.emit(lines)
	await dialogue_completed
	_dialogue_active = false

## Called by the battle UI once the player has clicked through all lines.
func close_dialogue() -> void:
	dialogue_completed.emit()


## Show placeholder cards for every cutscene slotted after the given wave index
## (0 = intro, K = after wave K, total_waves = outro). Each is gated by its own
## first-time/replay switch. Reuses the dialogue overlay for now; swap the body
## for an EventRunner call once the storyEvent -> event cpk mapping is resolved.
func _play_cutscenes_for_slot(slot: int) -> void:
	for cut in _cutscenes:
		if int(cut.get("after_wave", -1)) != slot:
			continue
		if _dialogue_gate_seen(cut.get("switch_non_info")):
			continue  # already seen
		var si: Variant = cut.get("switch_info")
		if _switch_present(si) and not SwitchService.is_unlocked(si):
			continue  # replay-only cutscene, not active yet
		await play_dialogue([_cutscene_placeholder_line(cut)])

## Builds a one-line placeholder card naming the cutscene that should play here,
## with the resolved event cpk (the folder id EventRunner takes) + resource id.
func _cutscene_placeholder_line(cut: Dictionary) -> Dictionary:
	var sid: String = str(cut.get("story_event_id", ""))
	var ev: Dictionary = GameDatabase.get_story_event(sid)
	var nm: String = str(ev.get("name", "?"))
	var scene_ref: String = str(ev.get("sceneRes", ""))       # "map@N" = layer/block
	var event_id: String = str(cut.get("event_id", ""))       # cpk folder for EventRunner
	var resource_id: String = str(cut.get("resource_id", ""))
	var line2: String = "storyEvent %s" % sid
	if scene_ref != "":
		line2 += "  ·  " + scene_ref
	var line3: String = "event %s  (resource %s)" % [
		event_id if event_id != "" else "?",
		resource_id if resource_id != "" else "?",
	]
	return {
		"speaker": "🎬 CUTSCENE (placeholder)",
		"text": "%s\n%s\n%s" % [nm, line2, line3],
	}

## True when a switch field is an active value (not null/""/"0"/"null").
func _switch_present(v: Variant) -> bool:
	if v == null:
		return false
	var s: String = str(v).strip_edges()
	return s != "" and s != "0" and s != "null"


func check_battle_state() -> void:
	# If we are already handling a win/loss, ignore further checks
	if is_transitioning:
		return

	# Check for Game Over first
	if _are_all_units_dead(player_units):
		is_transitioning = true
		_trigger_defeat()
		return

	# Check for Wave Clear
	if _are_all_units_dead(enemy_units):
		is_transitioning = true
		_trigger_wave_clear()
		return

	# Battle continues
	# print("BattleManager: Both sides still standing.")

func _trigger_defeat() -> void:
	if OS.is_debug_build():
		print("BattleManager: Defeat! All allies have fallen.")
	MissionService.request_finish_mission(false, current_mission_id, used_items)
	mission_failed.emit()

func _trigger_wave_clear() -> void:
	if OS.is_debug_build():
		print("BattleManager: Wave %d cleared!" % current_wave)

	# 1. Wait for the death tweens to finish (0.5 to 1.0 seconds)
	await get_tree().create_timer(1.0).timeout

	# Victory dialogue for the wave just cleared (gated by first-time switch).
	await play_dialogue(wave_dialogue_lines(current_wave, 2))

	# Cutscenes slotted after this wave -- mid-mission ones, and (when this is the
	# final wave) the outro, played before the mission-complete rewards.
	await _play_cutscenes_for_slot(current_wave)

	if current_wave >= total_waves:
		_trigger_mission_complete()
	else:
		# 2. Tell the UI to do the rolling number animation
		wave_transition_started.emit(current_wave, current_wave + 1, total_waves)

		# 3. Wait for the UI animation to finish before actually spawning
		await get_tree().create_timer(2.0).timeout

		await _spawn_next_wave()

func _trigger_mission_complete() -> void:
	if OS.is_debug_build():
		print("BattleManager: Final wave cleared. Initiating mission rewards...")
		print("Mission Drops: ", mission_drops)
		print("Unit EXP earned: ", mission_unit_exp)
		print("Battle gil earned: ", mission_gil)

	BattleEvents.mission_completed.emit(party_data, turn_count)
	
	for i in range(active_challenges.size()):
		var passed = active_challenges[i].evaluate()
		print("Challenge ", i, " passed: ", passed)
		challenge_results[i] = passed
		# Disconnect lambdas from the Autoload!
		active_challenges[i].cleanup()

	active_challenges.clear()

	MissionService.request_finish_mission(true, current_mission_id, used_items, challenge_results, mission_drops, mission_unit_exp, mission_gil)

	
func _spawn_next_wave() -> void:
	current_wave += 1
	if OS.is_debug_build():
		print("BattleManager: Spawning Wave %d..." % current_wave)

	var mission_data = MissionService.get_mission_data(str(current_mission_id))

	_spawn_wave(current_wave, mission_data)

	wave_changed.emit()

	current_state = BattleState.PLAYER_TURN
	player_units_acted_this_turn.clear()
	current_battle_frame = 0
	pending_hits.clear()
	pending_announcements.clear()

	# Clear queued actions so previous wave's selections don't bleed into the new wave.
	# Without this, BattleComIcon resets visually but execute_queued_action still reads
	# the stale queued_action/queued_action_id and fires the prior ability.
	for unit in party_data:
		if not unit.is_empty():
			_reset_unit_queued_action(unit)

	battle_state_ready.emit()

	# Start dialogue for the newly spawned wave (gated by first-time switch).
	await play_dialogue(wave_dialogue_lines(current_wave, 1))

	# Only unlock after everything is fully set up
	is_transitioning = false

func _roll_enemy_drops(enemy_data: Dictionary, enemy_index: int) -> void:
	var loot_table = enemy_data.get("loot", {})
	var drops = loot_table.get("drops", [])

	if drops.is_empty():
		return

	# 1. Global chance to drop absolutely nothing (e.g., 50% fail rate)
	if randf() > 0.50:
		return # No chest dropped!

	# 2. If we passed the global check, pick ONE random item from the pool
	var random_item_idx = randi() % drops.size()
	var selected_item_id = str(drops[random_item_idx])

	# 3. Add to escrow and emit
	mission_drops.append(selected_item_id)
	item_dropped.emit(enemy_index, selected_item_id)

## Adds a defeated enemy's unit EXP and gil yield (MONSTER_PARTS.exp / .gil,
## resolved onto the enemy dict at spawn) to the battle escrow. Held until the
## mission is completed, so a defeat forfeits everything earned this run.
func _accumulate_enemy_rewards(enemy_data: Dictionary) -> void:
	mission_unit_exp += maxi(0, int(enemy_data.get("exp", 0)))
	mission_gil += maxi(0, int(enemy_data.get("gil", 0)))

## Spawns the enemy formation for `wave_no` from the data-driven encounter chain
## (EncounterResolver). Missions with no resolvable formation get no enemies:
## exploration missions (type 2) are expected to be empty here (their encounters
## are random while traversing the map); any other type is a content gap and is
## logged as an error.
func _spawn_wave(wave_no: int, mission_data: Dictionary) -> void:
	enemy_units.clear()
	# AI state is keyed by enemy index, and both the indices and the monsters behind
	# them change with the formation. Flag banks and limited_act counters belong to one
	# monster in one encounter, so they must not survive into the next wave.
	_enemy_ai.clear()

	if wave_plan.size() > 0 and wave_no >= 1 and wave_no <= wave_plan.size():
		var wave: Dictionary = wave_plan[wave_no - 1]
		var formation: Array = EncounterResolver.resolve_formation(
			str(current_mission_id), str(wave.get("target_id", "")))
		if formation.size() > 0:
			for desc in formation:
				var enemy: Dictionary = _generate_enemy_from_descriptor(desc)
				enemy["team"] = "enemy"
				enemy["index"] = enemy_units.size()
				enemy_units.append(enemy)
			_print_wave_monster_ai(wave_no, formation)
			return

	if str(mission_data.get("type", "")) != "EXPLORATION":
		push_error("BattleManager: mission %s wave %d has no encounter data (no MISSION_PHASE or scenario battle)." % [current_mission_id, wave_no])


## Prints each spawned monster's resolved AI behaviour (skill set + scripted
## condition -> action rules) to the console, in the same structure as the
## resolve_monster_ai.py datamine tool. Runs as the wave's monster data is fetched.
func _print_wave_monster_ai(wave_no: int, formation: Array) -> void:
	print("\n########## Wave %d monster AI (mission %s) ##########" % [wave_no, current_mission_id])
	for desc in formation:
		MonsterAIResolver.print_behaviour(str(desc.get("instance_id", "")))


## Builds a combat-ready enemy dict from an EncounterResolver formation descriptor.
## Name, elemental resistances and loot drops come from the descriptor (sourced
## from the MONSTER_PARTS DB row); the combat stat block (hp/mp/atk/def/mag/spr)
## comes from MONSTER_PARTS keyed by the exact 9-digit monsterId, defaulting when
## no parts row exists.
func _generate_enemy_from_descriptor(desc: Dictionary) -> Dictionary:
	var enemy_data: Dictionary = {}
	enemy_data["id"] = str(desc.get("id", ""))
	enemy_data["instance_id"] = str(desc.get("instance_id", ""))
	enemy_data["name"] = str(desc.get("name", "Unknown Monster"))
	enemy_data["disp_pos"] = desc.get("disp_pos", Vector2.ZERO)
	enemy_data["is_boss"] = bool(desc.get("is_boss", false))
	enemy_data["loot"] = desc.get("loot", {})

	# Per-instance combat stats from MONSTER_PARTS (exact hp/mp/atk/def/mag/spr for
	# THIS spawn); modest defaults when the monster has no parts row.
	var parts: Dictionary = EncounterResolver.get_monster_parts_stats(str(desc.get("instance_id", "")))
	var combat_stats: Dictionary = _resolve_enemy_combat_stats(parts, {})

	var max_hp: int = int(combat_stats["HP"])
	enemy_data["max_hp"] = max_hp
	enemy_data["current_hp"] = max_hp
	enemy_data["hp"] = max_hp

	var max_mp: int = int(combat_stats["MP"])
	enemy_data["max_mp"] = max_mp
	enemy_data["current_mp"] = max_mp
	enemy_data["level"] = int(combat_stats["level"])
	# Unit EXP / gil this enemy yields when defeated (see _accumulate_enemy_rewards).
	enemy_data["exp"] = int(combat_stats["exp"])
	enemy_data["gil"] = int(combat_stats["gil"])

	# Marks this dict as a monster so StatCalculator.calculate_final_stats routes it to
	# MonsterStatCalculator. Without it, any recalculation (a debuff landing, a dispel,
	# the per-turn duration tick) would run a monster through the unit path and fail on
	# the first thing it looked for -- rarity, growth curves, equipment, trait skills.
	enemy_data["is_monster"] = true

	# Flat base stats, the input a recalculation works from. These have to live on the
	# instance rather than only inside final_stats: final_stats is the OUTPUT, so once a
	# buff or debuff lands there is nothing left to recompute from.
	enemy_data["base_stats"] = {
		"HP": max_hp,
		"MP": max_mp,
		"ATK": int(combat_stats["ATK"]),
		"DEF": int(combat_stats["DEF"]),
		"MAG": int(combat_stats["MAG"]),
		"SPR": int(combat_stats["SPR"]),
	}
	# Innate resistances stay in the datamine's raw comma-separated form, which is what
	# the shared resist decoder expects (`resistances` above is the parsed dictionary the
	# UI uses -- different consumer, different shape).
	enemy_data["elemResistValue"] = str(combat_stats.get("elemResistValue", ""))
	enemy_data["ailmentResistValue"] = str(combat_stats.get("ailmentResistValue", ""))
	enemy_data["active_effects"] = []

	# Combat damage formulas read attacker/target stats from final_stats.stats (same
	# shape as player units), so seed it the same way a unit's is seeded.
	enemy_data["final_stats"] = StatCalculator.calculate_final_stats(enemy_data)

	# Tracking variables (mirror _generate_enemy_data).
	enemy_data["chain_count"] = 0
	enemy_data["last_hit_frame"] = -100
	enemy_data["last_attacker_index"] = -1
	return enemy_data

## Resolves an enemy's combat stat block from its MONSTER_PARTS stats. Falls back
## to modest defaults when the monster has no parts row. Always returns keys
## HP, MP, ATK, DEF, MAG, SPR, level, exp, gil, elemResistValue, ailmentResistValue.
func _resolve_enemy_combat_stats(parts: Dictionary, _unused: Dictionary = {}) -> Dictionary:
	if not parts.is_empty():
		var parts_hp: int = int(parts.get("HP", 0))
		if parts_hp <= 0:
			parts_hp = DEFAULT_ENEMY_HP
		return {
			"HP": parts_hp,
			"MP": maxi(0, int(parts.get("MP", 0))),
			"ATK": maxi(1, int(parts.get("ATK", DEFAULT_ENEMY_STAT))),
			"DEF": maxi(1, int(parts.get("DEF", DEFAULT_ENEMY_STAT))),
			"MAG": maxi(1, int(parts.get("MAG", DEFAULT_ENEMY_STAT))),
			"SPR": maxi(1, int(parts.get("SPR", DEFAULT_ENEMY_STAT))),
			"level": maxi(1, int(parts.get("level", 1))),
			"exp": maxi(0, int(parts.get("exp", 0))),
			"gil": maxi(0, int(parts.get("gil", 0))),
			# Raw datamine strings, forwarded untouched for MonsterStatCalculator.
			"elemResistValue": str(parts.get("elemResistValue", "")),
			"ailmentResistValue": str(parts.get("ailmentResistValue", "")),
		}

	return {
		"HP": DEFAULT_ENEMY_HP,
		"MP": 0,
		"ATK": DEFAULT_ENEMY_STAT,
		"DEF": DEFAULT_ENEMY_STAT,
		"MAG": DEFAULT_ENEMY_STAT,
		"SPR": DEFAULT_ENEMY_STAT,
		"level": 1,
		"exp": 0,
		"gil": 0,
		"elemResistValue": "",
		"ailmentResistValue": "",
	}


# Helper function to grab only living units
static func _get_living_units(team_array: Array) -> Array[Dictionary]:
	return TargetResolver.get_living_units(team_array)

func _resolve_targets(target_area: int, target_type: int, caster: Dictionary, primary_target: Dictionary) -> Array[Dictionary]:
	var is_player_caster: bool = caster.get("team", "") == "player"
	# Pools are relative to the caster: enemy_pool is the opposing team, ally_pool is the caster's own team.
	# For player casters, allies are all party_data slots (stable indices, includes empty/dead slots).
	var enemy_pool: Array = enemy_units if is_player_caster else player_units
	var ally_pool: Array = party_data if is_player_caster else enemy_units
	return TargetResolver.resolve(target_area, target_type, caster, primary_target, enemy_pool, ally_pool)

## Resolves an effect's targets and queues its hits. `frame_offset` pushes the whole
## effect further down the timeline, which is how a multi-action enemy turn is spaced
## out instead of landing every hit on the same frame.
func _queue_effect_hits(effect: Dictionary, caster: Dictionary, primary_target: Dictionary, frame_offset: int = 0) -> void:
	var actual_targets: Array[Dictionary] = _resolve_targets(
		effect.get("target_area", 1),
		effect.get("target_type", 1),
		caster,
		primary_target
	)

	if effect.get("target_type", 1) == 1:
		actual_targets = CoverSystem.evaluate_interception(actual_targets, effect, _get_defending_pool(caster))

	var hit_payloads: Array[Dictionary] = action_processor.execute_parsed_effect(effect, caster, actual_targets)
	for hit in hit_payloads:
		hit["frame_to_execute"] += current_battle_frame + frame_offset
		hit["execute_on_frame"] = hit["frame_to_execute"]
		hit.erase("frame_to_execute")
		pending_hits.append(hit)

func _get_defending_pool(caster: Dictionary) -> Array:
	var caster_team: String = str(caster.get("team", "")).to_lower()
	return player_units if caster_team == "enemy" else enemy_units

func _on_turn_end(active_team: String) -> void:
	var defending_pool: Array = player_units if active_team.to_lower() == "enemy" else enemy_units
	CoverSystem.clear_transient_state(defending_pool)

## Executes a parsed skill against a primary target.
## target_area: 1 = single target, 2 = AOE.
## target_type: 1 = enemy, 2/6 = ally, 3 = self.
## Resolves the actual target list via TargetResolver, then queues per-effect hits.
func execute_parsed_skill(parsed_skill: Dictionary, caster: Dictionary, primary_target: Dictionary) -> void:
	var effects = parsed_skill.get("effects", [])
	for effect in effects:
		effect["element"] = parsed_skill.get("element_inflict")
		_queue_effect_hits(effect, caster, primary_target)
