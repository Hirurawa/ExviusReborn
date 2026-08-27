class_name RewardGranter
extends RefCounted

## Grants a single datamine reward entry to the player.
##
## Rewards are stored throughout the datamine as "type:id:amount:rate" strings
## (mission.rewards, challenge.rewardInfo, field_treasure.reward, quest.reward,
## ...), split into an Array by the caller. This is the one place that turns
## such an entry into inventory/profile mutations, so mission clears and town
## treasure chests hand out items identically.
##
## Callers are responsible for saving/emitting afterwards: the underlying
## services persist their own snapshots, but `InventoryService.emit_updated()`
## and `PlayerProfile.emit_all()` are left to the caller so a batch of rewards
## only refreshes the UI once.

## Grants `reward` and returns a description of what happened:
##   { granted: bool, typeId: int, type: String, id: String, amount: int,
##     name: String, iconFile: String }
## `granted` is false for reward types the game can't store yet (key items,
## recipes, vision cards) — the entry is still described so the caller can tell
## the player what they found.
static func grant(reward: Array) -> Dictionary:
	if reward.is_empty() or reward[0] == "<null>":
		return {"granted": false, "typeId": 0, "type": "", "id": "", "amount": 0, "name": "", "iconFile": ""}

	var info: Dictionary = GameDatabase.describe_reward(reward)
	info["granted"] = false
	var target_id: String = str(info.get("id", ""))
	var amount: int = int(info.get("amount", 1))

	match int(info.get("typeId", 0)):
		Types.Category_types.LAPIS:
			if amount > 0:
				PlayerProfile.add_lapis(amount)
				info["granted"] = true
				print("Granted %s Lapis" % amount)
		Types.Category_types.UNIT:
			UnitService._summon_fixed_units(target_id, 1, "Reward")
			info["granted"] = true
			print("Granted unit: " + target_id)
		Types.Category_types.ITEM:
			InventoryService.add_stackable(target_id, amount)
			info["granted"] = true
			print("Granted item: " + target_id)
		Types.Category_types.EQUIP:
			InventoryService.add_equipment_instances(target_id, amount)
			info["granted"] = true
			print("Granted equipment: " + target_id)
		Types.Category_types.MATERIA:
			InventoryService.grant_instanced_items("MATERIA", target_id, amount)
			info["granted"] = true
			print("Granted materia: " + target_id)
		_:
			push_warning("RewardGranter: unsupported reward type %s (%s x%d)" % [
				info.get("type", ""), info.get("name", target_id), amount
			])
	return info
