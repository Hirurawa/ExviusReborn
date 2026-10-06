class_name ChallengeSet
extends RefCounted

## The mission's challenges: one ChallengeTracker per challenge (ChallengeFactory), each
## listening to the BattleEvents autoload from the moment it is made. evaluate() reads
## them at victory; every way out of the battle (victory, defeat, the scene closing)
## must end in cleanup(), or the trackers' lambdas stay connected to the autoload and
## count the next battle too. Ported from the old BattleManager's initialize_challenges
## and _trigger_mission_complete.

var trackers: Array[ChallengeTracker] = []


## `challenges` is the mission data's `challenges` list ({ string, reward, parameter }).
func _init(challenges: Array = []) -> void:
	for data in challenges:
		var parameter: String = str((data as Dictionary).get("parameter", "")) if data is Dictionary else ""
		trackers.append(ChallengeFactory.create(parameter))


## The challenges of the mission in `params`; none for a battle group or the test
## battle.
static func for_params(params: Dictionary) -> ChallengeSet:
	if not params.has("mission_id"):
		return ChallengeSet.new()
	var mission: Dictionary = MissionService.get_mission_data(str(params["mission_id"]))
	var challenges: Variant = mission.get("challenges", [])
	return ChallengeSet.new(challenges if challenges is Array else [])


## Whether each challenge passed, in mission order, for MissionService. Disconnects the
## trackers.
func evaluate() -> Array[bool]:
	var results: Array[bool] = []
	for tracker in trackers:
		results.append(tracker.evaluate())
	cleanup()
	return results


## Disconnects every tracker from BattleEvents. Safe to call more than once.
func cleanup() -> void:
	for tracker in trackers:
		tracker.cleanup()
