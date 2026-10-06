class_name BattleScreen
extends Control

## The battle scene's root (BattleUI.tscn), on the new engine. It starts the battle
## through %BattleDirector, hands every engine event to the screen's areas, turns the
## player's gestures into session commands, runs auto battle, Reload and Repeat, and
## shows the mission's end. The areas draw and report input; this is the only script
## that talks to the session and the director, and it reads the engine, never writes it:
##   EnemyField   %EnemyRegion             enemy views, the target arrow, drops
##   PartyField   %PlayerSpritesContainer  party sprites, effects, crystals, cover
##   BattleMenus  %BottomUIWrapper         unit panels, skill and item menus, ally picks
##   BattleHud    (helper)                 labels, the top bar, esper gauge, wave counter
## UIManager.push("combat_ui", params) calls init_scene(params): { mission_id },
## { battle_group } (colosseum) or {} (the test battle).

const MissionResultScene: PackedScene = preload("res://features/battle/ui/MissionResultSequence.tscn")
const BATTLE_END_MUSIC: String = "res://assets/audio/bgm/la009_battleend.wav"
const COLOSSEUM_BACKGROUND: String = "Colosseum.jpg"

@onready var session: BattleSession = %BattleSession
@onready var director: BattleDirector = %BattleDirector
@onready var enemy_field: EnemyField = %EnemyRegion
@onready var party_field: PartyField = %PlayerSpritesContainer
@onready var menus: BattleMenus = %BottomUIWrapper
@onready var background: TextureRect = $Background
@onready var finish_button: Button = %FinishButton
@onready var rewards_popup: AcceptDialog = %RewardsPopup
@onready var unit_info_popup: UnitInfoPopup = %UnitInfoPopup
@onready var auto_button: TextureButton = $VisualLayer/CommandButtons/AutoButtonDecor
@onready var repeat_button: TextureButton = $VisualLayer/CommandButtons/MemoryButtonDecor
@onready var reload_button: TextureButton = %ReloadButtonDecor
@onready var limit_crystal: AnimatedSprite2D = $BattleLimitCrystal

var hud: BattleHud
var dialogue: BattleDialogue

## The enemy the player's attacks go to (-1 when none is standing).
var _target_enemy_id: int = -1
## A skill or item waiting for its ally pick: { unit_id, command, multicast }, the last
## true for a pick of the multicast draft.
var _pending: Dictionary = {}
## A multicast command the player is picking skills for: { unit_id, command, name, count,
## picks: Array[BattleCommand] }; {} when none.
var _draft: Dictionary = {}
## Unit id -> [hp, mp, lb] as last shown, so an event that carries one pool keeps the
## others where the events left them.
var _pools: Dictionary = {}
var _failure_shown: bool = false


func _ready() -> void:
	# Android's back button must not leave the battle.
	set_meta("block_back_request", true)
	# A real battle does not need the whole event log (the sandbox keeps it).
	session.keep_history = false
	hud = BattleHud.new(self)
	enemy_field.overlay = self
	party_field.overlay = self
	party_field.crystal_template = limit_crystal
	dialogue = BattleDialogue.new()
	add_child(dialogue)

	session.battle_started.connect(_on_battle_started)
	session.events_emitted.connect(_on_events)
	director.dialogue_requested.connect(dialogue.play)
	dialogue.finished.connect(_on_dialogue_finished)
	director.wave_transition_requested.connect(_on_wave_transition_requested)
	director.item_dropped.connect(enemy_field.show_drop)

	enemy_field.enemy_tapped.connect(_on_enemy_tapped)
	enemy_field.enemy_long_pressed.connect(_show_info)
	party_field.unit_long_pressed.connect(_show_info)
	menus.command_chosen.connect(_on_command_chosen)
	menus.unit_tapped.connect(_execute_unit)
	menus.skill_menu_requested.connect(_open_skill_menu)
	menus.item_menu_requested.connect(_open_item_menu)
	menus.option_picked.connect(_on_option_picked)
	menus.ally_picked.connect(_on_ally_picked)
	menus.ally_pick_cancelled.connect(_on_ally_pick_cancelled)
	menus.menu_dismissed.connect(_drop_draft)

	finish_button.pressed.connect(_on_finish_pressed)
	rewards_popup.confirmed.connect(_on_rewards_confirmed)
	auto_button.toggle_mode = true
	auto_button.toggled.connect(_on_auto_toggled)
	repeat_button.pressed.connect(_on_repeat_pressed)
	reload_button.pressed.connect(_on_reload_pressed)
	# The defeat comes from MissionService only (the old screen also listened to the
	# engine and showed it twice, KNOWN-BUGS #10).
	MissionService.mission_completed.connect(_on_mission_completed)
	MissionService.mission_failed.connect(_on_mission_failed)

	# Run on its own (F6), the scene opens the test battle. Its save, if any, goes to the
	# "default" scope, since no account is loaded.
	if get_tree().current_scene == self:
		init_scene.call_deferred({})


func _exit_tree() -> void:
	# MissionService outlives the battle; a closed screen must not answer it.
	if MissionService.mission_completed.is_connected(_on_mission_completed):
		MissionService.mission_completed.disconnect(_on_mission_completed)
	if MissionService.mission_failed.is_connected(_on_mission_failed):
		MissionService.mission_failed.disconnect(_on_mission_failed)


func init_scene(params: Dictionary) -> void:
	# One frame first, so a caller's loading overlay can render before the work.
	await get_tree().process_frame
	_apply_battle_background(str(params.get("mission_id", "")))
	director.start(params)


func _apply_battle_background(mission_id: String) -> void:
	var file_name: String = GameDatabase.get_mission_bg(mission_id) if mission_id != "" else COLOSSEUM_BACKGROUND
	var path: String = "res://assets/battle_bg/%s" % file_name
	if ResourceLoader.exists(path):
		background.texture = load(path)
	else:
		push_warning("BattleScreen: background not found at %s" % path)


# === Building the views ===

## A new battle: the party's panels and sprites (for the whole battle) and the first
## wave's enemies, before the start events arrive.
func _on_battle_started(engine: BattleEngine) -> void:
	_target_enemy_id = -1
	_pending = {}
	_draft = {}
	_pools.clear()
	var members: Array = []
	for member in engine.party_members():
		members.append({
			"id": member.id,
			"slot": member.slot,
			"template_id": member.template_id,
			"sprite_scale": _sprite_scale(member),
			"hp": member.hp,
			"max_hp": member.max_hp,
		})
		_pools[member.id] = [member.hp, member.mp, member.lb]
	menus.build(members)
	party_field.build(members)
	for member in engine.party_members():
		_show_pools(member)
		menus.panel(member.id).show_command(UnitPanel.ICON_ATTACK)
	_build_enemies(engine)
	hud.set_chain(0)
	hud.set_esper_gauge(engine.esper_orbs, engine.rules.esper_gauge_max)
	if not engine.enemies.is_empty():
		hud.play_wave_intro(engine.wave_count())


func _build_enemies(engine: BattleEngine) -> void:
	var rows: Array = []
	for foe in engine.enemies:
		rows.append({"id": foe.id, "template_id": foe.template_id, "disp_pos": foe.meta.get("disp_pos", Vector2.ZERO)})
	enemy_field.build(rows)
	_retarget(engine)


## Targets the first enemy on the field, as the engine falls back to when the pick is
## gone (an enemy in the air is out of reach).
func _retarget(engine: BattleEngine) -> void:
	var living: Array[Combatant] = engine.targetable(engine.living_enemies())
	if living.is_empty():
		_target_enemy_id = -1
		enemy_field.set_target(-1)
		hud.show_no_target()
	else:
		_set_target(living[0])


func _set_target(foe: Combatant) -> void:
	_target_enemy_id = foe.id
	enemy_field.set_target(foe.id)
	hud.show_target(foe.name, foe.hp, foe.max_hp)


## The unit's sprite scale: the third field of its spriteOffset, in percent.
static func _sprite_scale(member: Combatant) -> float:
	var parts: PackedStringArray = str(member.source.get("spriteOffset", "")).split(":")
	if parts.size() >= 3 and parts[2].is_valid_int() and int(parts[2]) > 0:
		return float(parts[2]) / 100.0
	return 1.0


# === Events ===

## Events arrive in batches (up to 16 ticks' worth at 4x). They are drawn in order, from
## their own numbers where they carry them, since the combatants may already be further
## on.
func _on_events(events: Array[Dictionary]) -> void:
	var engine: BattleEngine = session.engine
	for event in events:
		_handle(engine, event)


func _handle(engine: BattleEngine, event: Dictionary) -> void:
	match event["type"]:
		BattleEventLog.WAVE_STARTED:
			# The new wave's ids: rebuild before the rest of the batch looks for them.
			_build_enemies(engine)
		BattleEventLog.WAVE_CLEARED:
			_cancel_pick()
			_refresh_open_menu(engine)
		BattleEventLog.TURN_STARTED:
			_on_turn_started(engine, event)
		BattleEventLog.PHASE_CHANGED:
			# A turn that opens with reactions (counters, battle-start casts) hands over to
			# the player only afterwards.
			if StringName(event.get("phase", &"")) == &"player" and auto_button.button_pressed:
				_run_auto.call_deferred()
		BattleEventLog.COMMAND_QUEUED:
			_on_command_queued(engine, event)
		BattleEventLog.ACTION_STARTED:
			_on_action_started(engine, event)
		BattleEventLog.HIT_LANDED:
			_on_hit(engine, event)
		BattleEventLog.RESTORED:
			_on_pools(engine, int(event["target"]), event.get("hp_now"), event.get("mp_now"), null)
		BattleEventLog.REVIVED:
			_on_revived(engine, event)
		BattleEventLog.STATUS_DAMAGE:
			_on_pools(engine, int(event["target"]), event.get("hp"), null, null)
		BattleEventLog.COST_PAID:
			_on_pools(engine, int(event["actor"]), event.get("hp"), event.get("mp"), event.get("lb"))
			hud.set_esper_gauge(int(event.get("orbs", engine.esper_orbs)), engine.rules.esper_gauge_max)
		BattleEventLog.LB_CHANGED:
			_on_pools(engine, int(event["target"]), null, null, event.get("lb"))
		BattleEventLog.LB_CRYSTAL_DROPPED:
			_on_crystal(engine, event)
		BattleEventLog.ESPER_ORB_DROPPED, BattleEventLog.ESPER_GAUGE_CHANGED:
			hud.set_esper_gauge(int(event["orbs"]), int(event["max_orbs"]))
		BattleEventLog.ITEM_USED:
			_refresh_open_menu(engine)
		BattleEventLog.SKILL_GRANTED, BattleEventLog.SKILL_GRANT_ENDED:
			# A granted skill joins or leaves the unit's list. Op 99's branch only changes
			# when a turn starts, which already redraws the menu.
			if int(event["target"]) == menus.menu_unit_id:
				_refresh_open_menu(engine)
		BattleEventLog.COMBATANT_DEFEATED:
			_on_defeated(engine, event)
		BattleEventLog.STATUS_ADDED, BattleEventLog.STATUS_REMOVED:
			var fighter: Combatant = engine.combatant(int(event["target"]))
			if StringName(event.get("kind", &"")) == BattleStatus.AWAY:
				_on_away(engine, fighter, event["type"] == BattleEventLog.STATUS_ADDED)
			if fighter != null and fighter.is_party():
				_show_acted(fighter)
			if unit_info_popup.visible and unit_info_popup.shown_id == int(event["target"]):
				unit_info_popup.setup_from_combatant(fighter)
		BattleEventLog.COVER_ACTIVATED:
			if StringName(event.get("mode", &"")) == &"aoe":
				party_field.set_covering(int(event["coverer"]), true)
		BattleEventLog.COVER_ENDED:
			party_field.set_covering(int(event["coverer"]), false)


## A unit leaves the field (a jump) or comes back: its sprite rises out of sight or drops
## back. When the chosen enemy jumps, the target moves to the first enemy on the field.
func _on_away(engine: BattleEngine, fighter: Combatant, away: bool) -> void:
	if fighter == null:
		return
	if fighter.is_party():
		party_field.set_away(fighter.id, away)
		return
	enemy_field.set_away(fighter.id, away)
	if away and fighter.id == _target_enemy_id:
		_retarget(engine)
	elif not away and _target_enemy_id < 0 and fighter.is_alive():
		_set_target(fighter)


## The turn label restarts at 1 each wave (the engine's `turn`). Queued commands are
## gone, so every panel shows the attack again, or the jump for a unit ready to land it;
## a member that cannot take commands keeps the greyed look.
func _on_turn_started(engine: BattleEngine, event: Dictionary) -> void:
	hud.set_turn(int(event["turn"]))
	hud.set_chain(0)
	for member in engine.party_members():
		var landing: bool = engine.landing_ready(member)
		menus.panel(member.id).show_command(_command_icon(BattleCommand.Kind.LAND, &"") if landing else UnitPanel.ICON_ATTACK)
		party_field.play_queued(member.id, CombatSprite.AnimState.IDLE)
		_show_acted(member)
	_refresh_open_menu(engine)
	if auto_button.button_pressed:
		_run_auto.call_deferred()


func _on_command_queued(engine: BattleEngine, event: Dictionary) -> void:
	var member: Combatant = engine.combatant(int(event["actor"]))
	if member == null:
		return
	var kind: int = int(event["kind"])
	var skill_kind: StringName = StringName(event.get("skill_kind", &""))
	menus.panel(member.id).show_command(_command_icon(kind, skill_kind))
	party_field.play_queued(member.id, _queued_pose(kind, skill_kind))
	_refresh_open_menu(engine)


func _on_action_started(engine: BattleEngine, event: Dictionary) -> void:
	var actor: Combatant = engine.combatant(int(event["actor"]))
	if actor == null:
		return
	var kind: int = int(event["kind"])
	var origin: int = int(event["origin"])
	if actor.is_enemy():
		hud.show_feedback("%s - %s" % [actor.name, _action_text(event)])
		if kind == BattleCommand.Kind.ATTACK:
			enemy_field.play_attack(actor.id)
		return
	if kind == BattleCommand.Kind.DEFEND:
		menus.panel(actor.id).set_acted(true)
		return
	hud.show_feedback("%s - %s" % [actor.name, _action_text(event)])
	# A reaction (a counter, a passive's cast) does not use up the unit's turn; a landing
	# does.
	if origin == BattleAction.Origin.REACTION:
		if kind == BattleCommand.Kind.LAND:
			menus.panel(actor.id).set_acted(true)
		party_field.play_action(actor.id, _action_pose(kind))
	elif origin != BattleAction.Origin.CAST:
		menus.panel(actor.id).set_acted(true)
		party_field.play_action(actor.id, _action_pose(kind))
	if kind != BattleCommand.Kind.ATTACK:
		party_field.spawn_effects(_effect_frames(engine, actor, event), session.speed)


func _on_hit(engine: BattleEngine, event: Dictionary) -> void:
	hud.set_chain(int(event.get("chain", 0)))
	var target: Combatant = engine.combatant(int(event["target"]))
	if target == null:
		return
	var amount: int = int(event.get("amount", 0))
	if target.is_enemy():
		enemy_field.show_hit(target.id, amount)
		if target.id == _target_enemy_id:
			hud.show_target(target.name, int(event["hp"]), int(event["max_hp"]))
	else:
		party_field.show_hit(target.id, amount)
		_on_pools(engine, target.id, event.get("hp"), null, null)


func _on_revived(engine: BattleEngine, event: Dictionary) -> void:
	var fighter: Combatant = engine.combatant(int(event["target"]))
	if fighter == null:
		return
	if fighter.is_enemy():
		enemy_field.play_revive(fighter.id)
		if _target_enemy_id < 0:
			_set_target(fighter)
		return
	_on_pools(engine, fighter.id, event.get("hp"), null, null)
	_show_acted(fighter)


func _on_defeated(engine: BattleEngine, event: Dictionary) -> void:
	var fighter: Combatant = engine.combatant(int(event["target"]))
	if fighter == null:
		return
	if fighter.is_enemy():
		enemy_field.play_death(fighter.id)
		if fighter.id == _target_enemy_id:
			_retarget(engine)
	else:
		menus.panel(fighter.id).set_acted(true)
	# A KO'd member's queued item is free again.
	_refresh_open_menu(engine)


## A limit crystal flies from the enemy hit to the member; its gauge fills on arrival.
func _on_crystal(engine: BattleEngine, event: Dictionary) -> void:
	var member: Combatant = engine.combatant(int(event["target"]))
	if member == null:
		return
	var lb: int = int(event.get("lb", member.lb))
	var land: Callable = func() -> void: _on_pools(engine, member.id, null, null, lb)
	var start: Variant = enemy_field.sprite_position(int(event["source"]))
	if start == null:
		land.call()
	else:
		party_field.fly_crystal(start, member.id, land)


## Shows a party member's HP, MP and limit gauge, taking the values an event carries
## (null for those it does not); for an enemy, the top bar when it is the target.
func _on_pools(engine: BattleEngine, fighter_id: int, hp: Variant, mp: Variant, lb: Variant) -> void:
	var fighter: Combatant = engine.combatant(fighter_id)
	if fighter == null:
		return
	if fighter.is_enemy():
		if fighter.id == _target_enemy_id and hp != null:
			hud.show_target(fighter.name, int(hp), fighter.max_hp)
		return
	var shown: Array = _pools.get(fighter.id, [fighter.hp, fighter.mp, fighter.lb])
	if hp != null:
		shown[0] = int(hp)
	if mp != null:
		shown[1] = int(mp)
	if lb != null:
		shown[2] = int(lb)
	_pools[fighter.id] = shown
	_show_pools(fighter)


func _show_pools(member: Combatant) -> void:
	var shown: Array = _pools.get(member.id, [member.hp, member.mp, member.lb])
	var panel: UnitPanel = menus.panel(member.id)
	if panel != null:
		panel.show_stats(member.name, shown[0], member.max_hp, shown[1], member.max_mp, shown[2], member.max_lb)
	party_field.set_hp(member.id, shown[0], member.max_hp)


## Greyed when the member has acted, is KO'd or cannot take commands (sleep, stop, in the
## air...), unless it is in the air with a jump it can land now (its tap lands it).
func _show_acted(member: Combatant) -> void:
	var panel: UnitPanel = menus.panel(member.id)
	if panel != null:
		var landing: bool = session.engine != null and session.engine.landing_ready(member)
		panel.set_acted(member.acted or not member.is_alive() or (not member.can_take_commands() and not landing))


## "Attack", or the skill's name ("Skill" or "Item" when it has none).
static func _action_text(event: Dictionary) -> String:
	var text: String = _command_text(event)
	if int(event["kind"]) == BattleCommand.Kind.LAND:
		return "Landing: %s" % text
	match StringName(event.get("reaction", &"")):
		Reaction.COUNTER:
			return "Counter: %s" % text
		Reaction.BATTLE_START:
			return "Battle start: %s" % text
		Reaction.TURN_START:
			return "Turn start: %s" % text
		Reaction.REVIVE:
			return "Revived: %s" % text
		Reaction.DELAYED:
			return "Delayed: %s" % text
	return text


static func _command_text(event: Dictionary) -> String:
	var kind: int = int(event["kind"])
	if kind == BattleCommand.Kind.ATTACK:
		return "Attack"
	var skill_name: String = str(event.get("skill_name", ""))
	if skill_name != "":
		return skill_name
	return "Item" if kind == BattleCommand.Kind.ITEM else "Skill"


static func _command_icon(kind: int, skill_kind: StringName) -> String:
	match kind:
		BattleCommand.Kind.DEFEND:
			return UnitPanel.ICON_DEFEND
		BattleCommand.Kind.ITEM:
			return "item"
		BattleCommand.Kind.LIMIT_BURST:
			return "limit"
		BattleCommand.Kind.EVOKE:
			return "summon"
		BattleCommand.Kind.SKILL:
			return "magic" if skill_kind == BattleSkill.KIND_MAGIC else "special"
		BattleCommand.Kind.LAND:
			return "special"
	return UnitPanel.ICON_ATTACK


## The pose while a command waits: spells charge, abilities, limit bursts and espers
## stand by, the rest stay idle (the old screen's poses).
static func _queued_pose(kind: int, skill_kind: StringName) -> CombatSprite.AnimState:
	if kind == BattleCommand.Kind.SKILL and skill_kind == BattleSkill.KIND_MAGIC:
		return CombatSprite.AnimState.MAGIC_STANDBY
	if kind in [BattleCommand.Kind.SKILL, BattleCommand.Kind.LIMIT_BURST, BattleCommand.Kind.EVOKE]:
		return CombatSprite.AnimState.STANDBY
	return CombatSprite.AnimState.IDLE


static func _action_pose(kind: int) -> CombatSprite.AnimState:
	match kind:
		BattleCommand.Kind.LIMIT_BURST:
			return CombatSprite.AnimState.LIMIT_ATK
		BattleCommand.Kind.SKILL, BattleCommand.Kind.EVOKE:
			return CombatSprite.AnimState.MAGIC_ATK
	return CombatSprite.AnimState.ATK


## The effects of the skill an ACTION_STARTED names (its record's effect_frames), or of
## the ability it runs when the record has none (a cooldown wrapper).
static func _effect_frames(engine: BattleEngine, actor: Combatant, event: Dictionary) -> Array:
	var skill_id: String = str(event.get("skill_id", ""))
	var skill: BattleSkill = null
	if int(event["kind"]) == BattleCommand.Kind.LIMIT_BURST:
		skill = engine.catalog.get_limit_burst(skill_id, actor.limit_burst_level)
	else:
		skill = engine.catalog.get_skill(StringName(event.get("skill_kind", &"")), skill_id)
	var frames: Array = skill.record.get("effect_frames", []) if skill != null else []
	var executed_id: String = str(event.get("executed_skill_id", ""))
	if frames.is_empty() and executed_id != "" and executed_id != skill_id:
		var executed: BattleSkill = engine.catalog.get_skill(BattleSkill.KIND_ABILITY, executed_id)
		if executed != null:
			frames = executed.record.get("effect_frames", [])
	return frames


# === Input ===

func _on_command_chosen(unit_id: int, command: StringName) -> void:
	session.queue_command(unit_id, BattleCommand.defend() if command == UnitPanel.DEFEND else BattleCommand.attack())


## A tap on a panel: the unit acts, at the chosen enemy when its command aims at the
## other side or nothing is queued (a basic attack).
func _execute_unit(unit_id: int) -> void:
	_aim(unit_id)
	session.execute(unit_id)


## Points the unit's command at the chosen enemy, when it aims at opponents. A command
## with an ally pick keeps its target (KNOWN-BUGS #10); a multicast's picks without a
## target of their own take the enemy.
func _aim(unit_id: int) -> void:
	var engine: BattleEngine = session.engine
	var unit: Combatant = engine.combatant(unit_id) if engine != null else null
	# A landing hits the target picked at the jump (the wiki).
	if unit == null or unit.acted or unit.is_away() or _target_enemy_id < 0:
		return
	if not BattleCommandMenu.aims_at_opponents(engine, unit, unit.queued_command):
		return
	session.set_target(unit_id, _target_enemy_id)


func _on_enemy_tapped(enemy_id: int) -> void:
	if menus.is_picking_ally():
		menus.cancel_ally_pick()
		return
	var foe: Combatant = session.engine.combatant(enemy_id) if session.engine != null else null
	if foe != null and foe.is_targetable():
		_set_target(foe)


func _show_info(fighter_id: int) -> void:
	var fighter: Combatant = session.engine.combatant(fighter_id) if session.engine != null else null
	if fighter == null:
		return
	unit_info_popup.setup_from_combatant(fighter)
	unit_info_popup.move_to_front()
	unit_info_popup.show()


func _open_skill_menu(unit_id: int) -> void:
	var unit: Combatant = session.engine.combatant(unit_id)
	_draft = {}
	if unit != null:
		menus.show_skill_menu(unit_id, BattleCommandMenu.options(session.engine, unit))


func _open_item_menu(unit_id: int) -> void:
	var unit: Combatant = session.engine.combatant(unit_id)
	if unit != null:
		menus.show_item_menu(unit_id, BattleCommandMenu.item_options(session.engine, unit))


## Redraws the open menu: costs, holds and stock change as the battle goes on. A draft
## whose unit can no longer act is dropped.
func _refresh_open_menu(engine: BattleEngine) -> void:
	if not _draft.is_empty():
		var drafting: Combatant = engine.combatant(int(_draft["unit_id"]))
		if drafting == null or drafting.acted or not drafting.can_take_commands() or engine.phase != BattleEngine.Phase.PLAYER:
			_draft = {}
	var unit: Combatant = engine.combatant(menus.menu_unit_id)
	if unit == null:
		return
	if menus.open_menu == BattleMenus.MENU_SKILL and not _draft.is_empty() and int(_draft["unit_id"]) == unit.id:
		menus.refresh_menu(BattleCommandMenu.multicast_options(engine, unit, _draft["command"], _draft["picks"]))
	elif menus.open_menu == BattleMenus.MENU_SKILL:
		menus.refresh_menu(BattleCommandMenu.options(engine, unit))
	elif menus.open_menu == BattleMenus.MENU_ITEM:
		menus.refresh_menu(BattleCommandMenu.item_options(engine, unit))


## A skill or item from a menu: queued at once, or after the player picks an ally. A
## multicast command opens a draft instead, and while one is open the option is its next
## pick.
func _on_option_picked(unit_id: int, option: Dictionary) -> void:
	var engine: BattleEngine = session.engine
	var unit: Combatant = engine.combatant(unit_id)
	var command: BattleCommand = (option["command"] as BattleCommand).duplicate_command()
	var targeting: Dictionary = option.get("targeting", {})
	if not _draft.is_empty():
		if bool(targeting.get("needs_ally_pick", false)):
			_begin_ally_pick(engine, unit, command, targeting, true)
		else:
			_add_pick(engine, unit, command)
		return
	if int(option.get("multicast_count", 0)) > 0:
		var picks: Array[BattleCommand] = []
		_draft = {"unit_id": unit_id, "command": command, "name": str(option.get("name", "")),
			"count": int(option["multicast_count"]), "picks": picks}
		hud.show_feedback("%s: pick %d" % [_draft["name"], int(_draft["count"])])
		_show_draft(engine, unit, false)
		return
	if bool(targeting.get("needs_ally_pick", false)):
		_begin_ally_pick(engine, unit, command, targeting, false)
	elif session.queue_command(unit_id, command) == BattleEngine.OK:
		menus.close_menu()


func _begin_ally_pick(engine: BattleEngine, unit: Combatant, command: BattleCommand, targeting: Dictionary, for_draft: bool) -> void:
	var valid: Array = []
	for member in engine.party_members():
		if BattleCommandMenu.valid_ally(targeting, member, unit):
			valid.append(member.id)
	_pending = {"unit_id": unit.id, "command": command, "multicast": for_draft}
	menus.close_menu()
	menus.begin_ally_pick(valid)


## Adds a pick to the draft. The last one queues the multicast and closes the menu; until
## then the menu shows what the next pick can be (opened again when an ally pick closed
## it).
func _add_pick(engine: BattleEngine, unit: Combatant, pick: BattleCommand, reopen: bool = false) -> void:
	var picks: Array[BattleCommand] = _draft["picks"]
	picks.append(pick)
	if picks.size() < int(_draft["count"]):
		hud.show_feedback("%s: %d of %d" % [_draft["name"], picks.size(), int(_draft["count"])])
		_show_draft(engine, unit, reopen)
		return
	var command: BattleCommand = _draft["command"]
	command.picks = picks
	_draft = {}
	session.queue_command(unit.id, command)
	menus.close_menu()


## The skill menu of the draft's unit, drawn for its next pick. `reopen` slides it in
## again after an ally pick closed it (which also stops a slide-out still running).
func _show_draft(engine: BattleEngine, unit: Combatant, reopen: bool) -> void:
	var options: Array[Dictionary] = BattleCommandMenu.multicast_options(engine, unit, _draft["command"], _draft["picks"])
	if reopen:
		menus.show_skill_menu(unit.id, options)
	else:
		menus.refresh_menu(options)


func _drop_draft() -> void:
	_draft = {}


func _on_ally_picked(target_id: int) -> void:
	if _pending.is_empty():
		return
	var command: BattleCommand = _pending["command"]
	command.target_id = target_id
	var unit_id: int = int(_pending["unit_id"])
	var for_draft: bool = bool(_pending.get("multicast", false))
	_pending = {}
	if for_draft:
		if not _draft.is_empty():
			_add_pick(session.engine, session.engine.combatant(unit_id), command, true)
		return
	session.queue_command(unit_id, command)


## Cancel during a draft's ally pick drops that pick only: the menu comes back.
func _on_ally_pick_cancelled() -> void:
	var for_draft: bool = bool(_pending.get("multicast", false))
	_pending = {}
	if for_draft and not _draft.is_empty():
		var unit: Combatant = session.engine.combatant(int(_draft["unit_id"]))
		if unit != null:
			_show_draft(session.engine, unit, true)


func _cancel_pick() -> void:
	_draft = {}
	menus.cancel_ally_pick()
	_pending = {}


func _on_auto_toggled(enabled: bool) -> void:
	if not enabled:
		return
	if menus.is_picking_ally() or not _draft.is_empty():
		auto_button.set_pressed_no_signal(false)
		return
	_run_auto()


## Auto battle: every unit that can still act acts on the same frame, in party order.
## Waits while the director holds the battle for dialogue.
func _run_auto() -> void:
	var engine: BattleEngine = session.engine
	if not auto_button.button_pressed or menus.is_picking_ally() or not _draft.is_empty() or session.paused:
		return
	if engine == null or engine.phase != BattleEngine.Phase.PLAYER:
		return
	_execute_together(_ids(engine.units_to_act()))


func _execute_together(unit_ids: Array) -> void:
	for unit_id in unit_ids:
		_aim(unit_id)
	session.execute_many(unit_ids)


## Reload: each unit that can still act gets its last command back, when it is still
## allowed (BattleCommandMenu.restore_command). Returns those that got one.
func _restore_commands() -> Array:
	var restored: Array = []
	var engine: BattleEngine = session.engine
	if engine == null or menus.is_picking_ally() or not _draft.is_empty() or engine.phase != BattleEngine.Phase.PLAYER:
		return restored
	for unit in engine.units_to_act():
		var command: BattleCommand = BattleCommandMenu.restore_command(engine, unit)
		if command != null and session.queue_command(unit.id, command) == BattleEngine.OK:
			restored.append(unit.id)
	return restored


func _on_reload_pressed() -> void:
	if not _restore_commands().is_empty():
		hud.show_feedback("Reload last actions")


func _on_repeat_pressed() -> void:
	_execute_together(_restore_commands())


func _on_finish_pressed() -> void:
	finish_button.disabled = true
	director.debug_finish()


static func _ids(fighters: Array[Combatant]) -> Array:
	var ids: Array = []
	for fighter in fighters:
		ids.append(fighter.id)
	return ids


# === Director requests ===

func _on_dialogue_finished() -> void:
	director.dialogue_finished()
	if auto_button.button_pressed:
		_run_auto.call_deferred()


func _on_wave_transition_requested(wave: int, next_wave: int, waves: int) -> void:
	_cancel_pick()
	var rolled: Signal = hud.play_wave_transition(wave, next_wave, waves)
	await rolled
	director.transition_finished()


# === Mission end ===

func _on_mission_completed(result: Dictionary) -> void:
	AudioService.play_music(BATTLE_END_MUSIC, false)
	var engine: BattleEngine = session.engine
	# The surviving party celebrates before the result screen takes over.
	await party_field.play_victory(_ids(engine.living_party()))
	var sequence: Node = MissionResultScene.instantiate()
	add_child(sequence)
	sequence.start(result, BattleEventsBridge.party_sources(engine, PartyService.SLOT_COUNT))
	sequence.finished.connect(_on_result_sequence_finished)


func _on_mission_failed(error_msg: String = "") -> void:
	if _failure_shown:
		return
	_failure_shown = true
	print("Failed to complete mission: %s" % error_msg)
	AudioService.play_music(BATTLE_END_MUSIC, false)
	rewards_popup.dialog_text = "Mission Failed!"
	rewards_popup.popup_centered()


func _on_rewards_confirmed() -> void:
	UIManager.pop()


func _on_result_sequence_finished() -> void:
	UIManager.pop()
