class_name BattleHud
extends RefCounted

## The battle screen's labels and gauges, which span several nodes of BattleUI.tscn:
## the targeted enemy's name and HP bars, the turn and chain labels, the action feedback
## line, the party's esper (summon) gauge, and the wave counter with its roll between
## waves. A helper holding the nodes; the battle screen pushes values in.

const ACTION_FEEDBACK_SECONDS: float = 1.5
const WAVE_FADE_SECONDS: float = 0.3
const WAVE_INTRO_HOLD_SECONDS: float = 1.0
const WAVE_ROLL_HOLD_SECONDS: float = 0.5
const WAVE_ROLL_SECONDS: float = 0.4

var _host: Control
var _turn_label: Label
var _chain_label: Label
var _enemy_name: Label
var _enemy_hp_bar: ProgressBar
var _enemy_hp_pct: Label
var _enemy_hp_sprite: Sprite2D
var _feedback: Label
var _transition: Control
var _esper_gauge: Range
## A newer feedback line wins: only the latest one hides itself.
var _feedback_token: int = 0


## `host` is the battle screen's root (BattleUI.tscn), which owns the nodes and runs the
## tweens.
func _init(host: Control) -> void:
	_host = host
	_turn_label = host.get_node("%TurnLabel")
	_chain_label = host.get_node("%ChainCountLabel")
	_enemy_name = host.get_node("%EnemyNameLabel")
	_enemy_hp_bar = host.get_node("%EnemyHPBar")
	_enemy_hp_pct = host.get_node("%EnemyHPPctLabel")
	_enemy_hp_sprite = host.get_node("BattleEnemyHpBar1")
	_feedback = host.get_node("%ActionFeedbackLabel")
	_transition = host.get_node("%TransitionUI")
	_esper_gauge = host.get_node("VisualLayer/SummonGaugeBg/BattleSummonBar")


func set_turn(turn: int) -> void:
	_turn_label.text = "Turn %d" % turn


func set_chain(chain: int) -> void:
	_chain_label.text = "Chain: %d" % chain


## The top bar for the targeted enemy.
func show_target(enemy_name: String, hp: int, max_hp: int) -> void:
	_enemy_name.text = enemy_name
	var ratio: float = clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	_enemy_hp_sprite.scale.x = ratio
	_enemy_hp_bar.max_value = max_hp
	_enemy_hp_bar.value = hp
	_enemy_hp_pct.text = "%d%%" % int(ratio * 100.0)


## No enemy left to target (the wave is down).
func show_no_target() -> void:
	_enemy_name.text = "Cleared"


## Shows `text` ("Unit - Skill") for ACTION_FEEDBACK_SECONDS.
func show_feedback(text: String) -> void:
	_feedback.text = text
	_feedback.visible = true
	_feedback.modulate.a = 1.0
	_feedback_token += 1
	var token: int = _feedback_token
	var tween: Tween = _host.create_tween()
	tween.tween_interval(ACTION_FEEDBACK_SECONDS)
	tween.tween_callback(func() -> void:
		if token == _feedback_token:
			_feedback.visible = false)


## The party's esper gauge: `orbs` of `max_orbs`.
func set_esper_gauge(orbs: int, max_orbs: int) -> void:
	_esper_gauge.max_value = maxi(1, max_orbs)
	_esper_gauge.value = orbs


## "Wave 1 / N" fades in, holds and fades out as the battle opens.
func play_wave_intro(total_waves: int) -> void:
	_wave_labels("1", "", total_waves)
	_transition.show()
	_transition.modulate.a = 0.0
	var tween: Tween = _host.create_tween()
	tween.tween_property(_transition, "modulate:a", 1.0, WAVE_FADE_SECONDS)
	tween.tween_interval(WAVE_INTRO_HOLD_SECONDS)
	tween.tween_property(_transition, "modulate:a", 0.0, WAVE_FADE_SECONDS)
	tween.tween_callback(_transition.hide)


## The wave counter rolls from `wave` to `next_wave` of `total_waves`. Returns the
## signal emitted when the roll is over.
func play_wave_transition(wave: int, next_wave: int, total_waves: int) -> Signal:
	var labels: Array[Label] = _wave_labels(str(wave), str(next_wave), total_waves)
	_transition.show()
	_transition.modulate.a = 0.0
	var tween: Tween = _host.create_tween()
	tween.tween_property(_transition, "modulate:a", 1.0, WAVE_FADE_SECONDS)
	tween.tween_interval(WAVE_ROLL_HOLD_SECONDS)
	# The odometer push: the current number rolls up and out as the next one rolls in.
	tween.parallel().tween_property(labels[0], "position:y", -60, WAVE_ROLL_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(labels[1], "position:y", 0, WAVE_ROLL_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(WAVE_ROLL_HOLD_SECONDS)
	tween.tween_property(_transition, "modulate:a", 0.0, WAVE_FADE_SECONDS)
	tween.tween_callback(_transition.hide)
	return tween.finished


## Sets the counter's labels and puts the two numbers back in place; returns
## [current, next].
func _wave_labels(current: String, next: String, total_waves: int) -> Array[Label]:
	var current_num: Label = _transition.get_node("HBox/NumberMask/CurrentNum")
	var next_num: Label = _transition.get_node("HBox/NumberMask/NextNum")
	var total_label: Label = _transition.get_node("HBox/TotalWavesLabel")
	current_num.text = current
	next_num.text = next
	total_label.text = " / " + str(total_waves)
	current_num.position.y = 0
	next_num.position.y = 50
	var labels: Array[Label] = [current_num, next_num]
	return labels
