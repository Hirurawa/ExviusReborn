extends "res://tests/test_case.gd"

## The shared Skill button (features/shared/skill.gd) shows the overlay of each "lack"
## reason BattleCommandMenu gives (MP, limit, summon) and greys out with no overlay for
## any other reason.

const SKILL_SCENE: PackedScene = preload("res://features/shared/Skill.tscn")
const SkillButton = preload("res://features/shared/skill.gd")

var _button: Control = null


func before_each() -> void:
	_button = SKILL_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(_button)


func after_each() -> void:
	_button.get_parent().remove_child(_button)
	_button.queue_free()


func _overlay() -> TextureRect:
	return _button.get_node("unit_magic_unavailable_reason_1")


func test_each_lack_reason_has_its_overlay() -> void:
	var expected: Dictionary = {
		BattleCommandMenu.REASON_LACK_MP: SkillButton.LACK_MP_TEXTURE,
		BattleCommandMenu.REASON_LACK_LIMIT: SkillButton.LACK_LIMIT_TEXTURE,
		BattleCommandMenu.REASON_LACK_SUMMON: SkillButton.LACK_SUMMON_TEXTURE,
	}
	for reason in expected:
		_button.set_action_availability(false, reason)
		assert_true(_overlay().visible, reason)
		assert_eq(_overlay().texture, expected[reason], reason)
		assert_true(_button.get_node("Button").disabled, reason)


func test_other_reasons_grey_the_button_without_an_overlay() -> void:
	_button.set_action_availability(false, BattleCommandMenu.REASON_UNAVAILABLE)
	assert_false(_overlay().visible)
	assert_true(_button.get_node("Button").disabled)
	assert_ne(_button.modulate, Color.WHITE, "greyed")
	_button.set_action_availability(false, "unit_unavailable")
	assert_false(_overlay().visible, "the old battle UI's reason for a KO'd unit")


func test_an_enabled_button_has_no_overlay() -> void:
	_button.set_action_availability(false, BattleCommandMenu.REASON_LACK_MP)
	_button.set_action_availability(true)
	assert_false(_overlay().visible)
	assert_false(_button.get_node("Button").disabled)
	assert_eq(_button.modulate, Color.WHITE)
