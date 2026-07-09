extends RefCounted
class_name TargetResolver

## Pure functions that resolve a target list for an effect, given the caster and
## primary target. Extracted from BattleManager to make targeting unit-testable
## without standing up a full battle.
##
## target_area: 1 = single target, 2 = AOE
## target_type: 1 = enemy (opposing team), 2/6 = ally (own team), 3 = self


## Returns only the living units (non-empty, current_hp > 0) from `team_array`.
static func get_living_units(team_array: Array) -> Array[Dictionary]:
	var living: Array[Dictionary] = []
	for unit in team_array:
		if not unit.is_empty() and unit.get("current_hp", 0) > 0:
			living.append(unit)
	return living


## Resolves the actual target list for an effect.
## - `caster_enemy_pool`: the team opposing the caster.
## - `caster_ally_pool`: the caster's own team (may include empty/dead slots for stable indexing).
## Cover interception is applied separately by the caller.
static func resolve(target_area: int, target_type: int, caster: Dictionary, primary_target: Dictionary, caster_enemy_pool: Array, caster_ally_pool: Array) -> Array[Dictionary]:
	# TYPE 3: SELF
	if target_type == 3:
		return [caster]

	# TYPE 1: ENEMY (opposing team) - never target dead enemies
	if target_type == 1:
		var living_enemies: Array[Dictionary] = get_living_units(caster_enemy_pool)
		if living_enemies.is_empty():
			return [] # Win condition safety

		if target_area == 2:
			return living_enemies
		# Single Target
		if primary_target.get("current_hp", 0) > 0:
			return [primary_target]
		return [living_enemies[0]] # Fallback to first alive if intended target died

	# TYPE 2/6: ALLY (own team)
	if target_type == 2: # Living allies
		if target_area == 2:
			var living_allies: Array[Dictionary] = get_living_units(caster_ally_pool)
			if living_allies.is_empty():
				return []
			return living_allies
		# Single Target
		if not primary_target.is_empty() and primary_target.get("current_hp", 0) > 0:
			return [primary_target]
		return [caster]
	
	if target_type == 6: # Can target dead units
		if target_area == 2:
			return caster_ally_pool
		# Single Target - dead allies are valid (e.g. revive)
		if not primary_target.is_empty():
			return [primary_target]
		return [caster]
	
	# Fallback catch-all
	return []
