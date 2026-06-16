extends RefCounted
class_name EncounterResolver

## Resolves the data chain Mission -> Wave(s) -> Formation -> Monsters for combat,
## mirroring the FFBE datamine relationships:
##
##   MISSION_PHASE (ordered by phaseNum) gives the real wave sequence. A battle
##   phase (not gated by switchInfo, and either battleBgId != 0 OR a targetId that
##   resolves to a formation) points at a BATTLE_LOTTERY pool (weighted
##   formations) or directly at a BATTLE_GROUP (a guaranteed formation).
##   BATTLE_GROUP lists the monster slots (monsterId + dispPos).
##
##   Boss / story / exploration missions have NO MISSION_PHASE. Their waves come
##   from LOCATION_SCENARIO_BATTLE (locationType 1, targetId == missionId) ->
##   scenarioBattleInfo -> SCENARIO_BATTLE (scenarioBattleId -> battleGroupId) ->
##   BATTLE_GROUP.
##
##   monsterId (9-digit slot id) -> dictionaryId (7-digit) which is both the
##   sprite id used by TextureBuilder / combat_sprite and the MONSTER_DICTIONARY
##   key for the display name. The dictionaryId, name, per-instance combat stats,
##   elemental resists and loot drops all come from the MONSTER_PARTS row.
##
## DATA SOURCE: every encounter table (MISSION_PHASE / BATTLE_LOTTERY /
## BATTLE_GROUP / MONSTER_PARTS / MONSTER_DICTIONARY / LOCATION_SCENARIO_BATTLE /
## SCENARIO_BATTLE) is queried per-mission from the bundled SQLite DB
## (GameDatabase) on demand — only the handful of rows a mission needs are read.
## Combat no longer touches any JSON dataset.

# Element order of MONSTER_PARTS.elemResistValue (comma-separated). A trailing
# 9th value exists in the data and is ignored.
const _RESIST_ELEMENTS: Array = [
	"fire", "ice", "lightning", "water", "wind", "earth", "light", "dark",
]

# dropInfo reward type code for a normal item (the only loot type the drop roll
# consumes). Format per entry: "type:id:?:?".
const _DROP_TYPE_ITEM: String = "20"


## Back-compat hook. Every encounter table is queried on demand from the DB, so
## there is no longer any up-front build step. Kept as a no-op so existing
## callers don't break.
static func ensure_built() -> void:
	pass


## Returns true if the mission has a data-driven wave plan (phases or scenarios).
static func has_wave_plan(mission_id: String) -> bool:
	return not build_wave_plan(mission_id).is_empty()


## Returns the ordered wave plan for a mission as an array of:
##   { "target_id": String, "phase_num": int, "is_boss": bool }
## `target_id` is fed to `resolve_formation`. Empty array => no data-driven plan
## (caller should fall back to its legacy spawner). `is_boss` here is a hint for
## scenario waves; `resolve_formation` always sets the authoritative per-monster flag.
static func build_wave_plan(mission_id: String) -> Array:
	var plan: Array = []

	# 1) Authoritative wave sequence from MISSION_PHASE (regular encounters),
	#    read straight from the DB and already ordered by phaseNum.
	var phases: Array = GameDatabase.get_mission_phases(mission_id)
	if not phases.is_empty():
		var n: int = 0
		for row in phases:
			n += 1
			plan.append({"target_id": str(row.get("targetId", "")), "phase_num": n, "is_boss": false})
		return plan

	# 2) Boss / story / exploration missions have no MISSION_PHASE; their waves
	#    come from the scenario-battle chain (LOCATION_SCENARIO_BATTLE ->
	#    SCENARIO_BATTLE -> battleGroupId), resolved straight from the DB. Every
	#    scenario battle is one guaranteed boss/story wave.
	var wave_idx: int = 0
	for bg_id in GameDatabase.get_mission_scenario_groups(mission_id):
		wave_idx += 1
		plan.append({
			"target_id": str(bg_id),
			"phase_num": wave_idx,
			"is_boss": true,
		})
	return plan


## The set (as a Dictionary used like a set) of battleGroupIds that are
## guaranteed boss/story fights for the mission (the scenario-battle groups).
static func get_boss_groups(mission_id: String) -> Dictionary:
	var groups: Dictionary = {}
	for bg_id in GameDatabase.get_mission_scenario_groups(mission_id):
		groups[str(bg_id)] = true
	return groups


## Resolves a wave `target_id` to a concrete monster formation. Returns an array
## of monster spawn descriptors:
##   { "id": String (7-digit dictionaryId / sprite id),
##     "instance_id": String (9-digit monsterId),
##     "name": String, "disp_pos": Vector2, "is_boss": bool }
static func resolve_formation(mission_id: String, target_id: String) -> Array:
	var battle_group_id: String = _pick_battle_group(target_id)
	if battle_group_id == "":
		return []

	var is_boss: bool = get_boss_groups(mission_id).has(battle_group_id)
	var rows: Array = GameDatabase.get_battle_group(battle_group_id)  # ordered by dispOrder

	# Prefer initially-displayed slots; reinforcement slots (initialDisp == 0)
	# are out of scope for the current battle system.
	var initial_rows: Array = []
	for row in rows:
		if str(row.get("initialDisp", "1")) != "0":
			initial_rows.append(row)
	if initial_rows.is_empty():
		initial_rows = rows

	var formation: Array = []
	for row in initial_rows:
		var monster_id: String = str(row.get("monsterId", ""))
		if monster_id == "":
			continue
		# One parts lookup feeds the dictionaryId, display name, elemental resists
		# and loot drops for this monster (its combat stat block is fetched
		# separately by the battle manager via get_monster_parts_stats).
		var parts: Dictionary = GameDatabase.get_monster_parts(monster_id)
		var dict_id: String = _dictionary_id_for(parts, monster_id)
		formation.append({
			"id": dict_id,
			"instance_id": monster_id,
			"name": _resolve_name(parts, dict_id),
			"disp_pos": _parse_disp_pos(row.get("dispPos", "")),
			"is_boss": is_boss,
			"resistances": _parse_resistances(str(parts.get("elemResistValue", ""))),
			"loot": {"drops": _parse_loot_drops(str(parts.get("dropInfo", "")))},
		})
	return formation


## Parses MONSTER_PARTS.elemResistValue ("fire,ice,lightning,water,wind,earth,
## light,dark[,extra]") into a { element: int } dictionary. The trailing 9th
## value is ignored. Missing/short values default to 0.
static func _parse_resistances(raw: String) -> Dictionary:
	var out: Dictionary = {}
	var parts: PackedStringArray = raw.split(",", false)
	for i in range(_RESIST_ELEMENTS.size()):
		var val: int = 0
		if i < parts.size() and str(parts[i]).is_valid_int():
			val = int(parts[i])
		out[_RESIST_ELEMENTS[i]] = val
	return out


## Parses MONSTER_PARTS.dropInfo ("type:id:?:?,...") into a list of item-id
## strings (entries whose type is the item code). Blank/"0" -> [].
static func _parse_loot_drops(raw: String) -> Array:
	var drops: Array = []
	if raw == "" or raw == "0":
		return drops
	for chunk in raw.split(",", false):
		var fields: PackedStringArray = str(chunk).split(":")
		if fields.size() >= 2 and str(fields[0]) == _DROP_TYPE_ITEM:
			drops.append(str(fields[1]))
	return drops


## Returns the per-instance combat stat block for a 9-digit monsterId (the id
## BATTLE_GROUP references), or {} if absent. Keys are game stat names:
##   HP, MP, ATK, DEF, MAG (from intl), SPR (from mnd), plus level/exp/gil.
static func get_monster_parts_stats(monster_id: String) -> Dictionary:
	var p: Dictionary = GameDatabase.get_monster_parts(monster_id)
	if p.is_empty():
		return {}
	# Map the raw datamine columns to in-game stat keys (intl -> MAG, mnd -> SPR).
	return {
		"HP": int(p.get("hp", 0)),
		"MP": int(p.get("mp", 0)),
		"ATK": int(p.get("atk", 0)),
		"DEF": int(p.get("def", 0)),
		"MAG": int(p.get("intl", 0)),
		"SPR": int(p.get("mnd", 0)),
		"level": int(p.get("level", 1)),
		"exp": int(p.get("exp", 0)),
		"gil": int(p.get("gil", 0)),
	}


# --- Resolution internals --------------------------------------------------

## Picks a single battleGroupId for a target: a BATTLE_LOTTERY pool (weighted)
## takes precedence; otherwise the target is itself a guaranteed battleGroupId.
static func _pick_battle_group(target_id: String) -> String:
	var members: Array = GameDatabase.get_lottery_pool(target_id)
	if not members.is_empty():
		return _weighted_pick(members)
	if GameDatabase.has_battle_group(target_id):
		return target_id
	return ""


## Weighted random selection over BATTLE_LOTTERY rows ({battleGroupId, weight}).
static func _weighted_pick(members: Array) -> String:
	var total: int = 0
	for m in members:
		total += int(m.get("weight", 0))
	if total <= 0:
		return str(members[0].get("battleGroupId", ""))
	var roll: int = randi() % total
	var acc: int = 0
	for m in members:
		acc += int(m.get("weight", 0))
		if roll < acc:
			return str(m.get("battleGroupId", ""))
	return str(members[members.size() - 1].get("battleGroupId", ""))


## dictionaryId (7-digit sprite/bestiary id) for a 9-digit monsterId: taken from
## the MONSTER_PARTS row when present, else derived from the standard id scheme.
static func _dictionary_id_for(parts: Dictionary, monster_id: String) -> String:
	var dict_id: String = str(parts.get("dictionaryId", ""))
	if dict_id != "":
		return dict_id
	if monster_id.is_valid_int():
		return str((int(monster_id) / 1000) * 10)
	return monster_id


## Display name following the datamine path monsterId -> dictionaryId ->
## MONSTER_DICTIONARY.name (DB). Falls back to the MONSTER_PARTS row name, then
## a stub.
static func _resolve_name(parts: Dictionary, dictionary_id: String) -> String:
	var dict_name: String = GameDatabase.get_monster_name(dictionary_id)
	if dict_name != "":
		return dict_name
	var nm: String = str(parts.get("name", ""))
	if nm != "":
		return nm
	return "Unknown Monster"


static func _parse_disp_pos(value: Variant) -> Vector2:
	var parts: PackedStringArray = str(value).split(",", false)
	if parts.size() >= 2 and str(parts[0]).is_valid_int() and str(parts[1]).is_valid_int():
		return Vector2(int(parts[0]), int(parts[1]))
	return Vector2.ZERO
