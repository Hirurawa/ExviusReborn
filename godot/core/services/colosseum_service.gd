extends Node

const SNAPSHOT_FILE: String = "colosseum.json"

var round: int = 10101
var points: int = 0
var next_battle: int = 0


func start_colosseum(selected_round: int) -> void:
	var battle_data = get_battle_info(selected_round)
	_on_colosseum_battle_finished(selected_round)


func _on_colosseum_battle_finished(selected_round: int) -> void:
	if round == selected_round:
		var round_info = GameDatabase.get_clsm_round(round)
		if points == 0:
			print("First clear")
			RewardGranter.grant(round_info.get("reward").split(':'))
		else:
			print("Repeat reward")
			RewardGranter.grant(round_info.get("repeatReward").split(':'))
		if points >= 1000:
			round = get_colosseum_progress().get("nextRoundId")
			points = 0
		else:
			points += 100
			next_battle = (next_battle + 1) % 5
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "colosseum_start")


func get_colosseum_progress() -> Dictionary:
	var progress = GameDatabase.get_clsm_progress(round)
	return {
		"grade": progress.get("grade", "?"),
		"rankId": progress.get("rankId", 0),
		"rank": progress.get("rank", "?"),
		"roundId": progress.get("roundId", "??????"),
		"nextRoundId": progress.get("nextRoundId"),
		"points": points
		}


func get_battle_info(selected_round: int) -> Dictionary:
	var battle_group
	if points == 1000:
		battle_group = GameDatabase.get_clsm_monster_group(selected_round, true)[0]
	else:
		battle_group = GameDatabase.get_clsm_monster_group(selected_round)[next_battle]
	var battle_data = GameDatabase.get_battle_group(str(battle_group.get("battleGroupId")))
	return {"name": battle_group.get("name", "?"), "battle_group_id": battle_group.get("battleGroupId") ,"battle_data": battle_data}


func snapshot_payload() -> Dictionary:
	return {"round": round, "points": points, "next_battle": next_battle}


func load_progress() -> void:
	var envelope: Dictionary = Persistence.load_snapshot(SNAPSHOT_FILE)
	if envelope.is_empty():
		round = 0

	var data: Variant = envelope.get("data", {})
	if not (data is Dictionary):
		round = 0

	round = data.get("round", 10101)
	points = data.get("points", 0)
	next_battle = data.get("next_battle", 0)
