extends Node
## GameDatabase — read-only access to the bundled SQLite datamine (ffbe-data.db).
##
## A single shared connection, opened lazily on first query. Rows come back as
## plain Array[Dictionary] (column name -> value), so callers can treat them like
## the old JSON `records` arrays they replaced.
##
## WHY WE COPY THE DB TO user://: the bundled database lives at res://, which in an
## exported build is inside the (read-only) PCK. The godot-sqlite plugin can't open
## a database packed inside the PCK — its VFS resolves res:// to a real OS path that
## doesn't exist there, so open_db() fails with "unable to open database file". So
## on first launch (and whenever the bundled DB changes) we copy it out to user://
## — a real writable directory on every platform (Windows, Android, ...) — and open
## it from there. The DB is in rollback (DELETE) journal mode, so a plain read_only
## connection needs no sidecar files.
##
## First consumer is the world map (features/outgame/map/map_ui.gd); this is the
## pilot for migrating per-table JSON static data over to the database.

# Bundled database shipped inside the PCK, and its writable runtime copy.
const BUNDLED_DB_PATH: String = "res://assets/static_data/ffbe-data.db"
const USER_DB_PATH: String = "user://ffbe-data.db"
# Sidecar recording the byte size of the bundled DB the user copy was made from,
# so a re-exported/updated database is detected and re-copied.
const USER_DB_META_PATH: String = "user://ffbe-data.db.meta"

var _db: SQLite = null
var _open_failed: bool = false


# === Connection ===

func _ensure_open() -> bool:
	if _db != null:
		return true
	# Don't keep retrying a connection we already know is broken/missing.
	if _open_failed:
		return false

	var db_path: String = _ensure_local_db()
	if db_path == "":
		_open_failed = true
		push_error("GameDatabase: bundled database missing or could not be copied from %s" % BUNDLED_DB_PATH)
		return false

	var db: SQLite = SQLite.new()
	db.path = db_path
	db.read_only = true # static data; never written. DB is DELETE-journal so no sidecars.
	db.verbosity_level = 0 # QUIET — don't log every query to the console
	if not db.open_db():
		_open_failed = true
		push_error("GameDatabase: could not open %s (%s)" % [db_path, db.error_message])
		return false

	_db = db
	return true


## Ensures a current, writable copy of the bundled database exists in user:// and
## returns its path (or "" if the bundled DB can't be read). The copy is refreshed
## whenever the bundled DB's byte size differs from the one recorded at copy time,
## so a re-exported database is picked up automatically.
func _ensure_local_db() -> String:
	var bundled_size: int = _file_size(BUNDLED_DB_PATH)
	if bundled_size <= 0:
		# Bundled DB unreadable — fall back to an existing copy if we have one.
		return USER_DB_PATH if FileAccess.file_exists(USER_DB_PATH) else ""

	if FileAccess.file_exists(USER_DB_PATH) and _read_int(USER_DB_META_PATH) == bundled_size:
		return USER_DB_PATH

	# (Re)copy the bundled DB out to user://. FileAccess reads res:// straight from
	# the PCK fine (it's only the SQLite VFS that can't), so a byte copy works.
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(BUNDLED_DB_PATH)
	if bytes.is_empty():
		return USER_DB_PATH if FileAccess.file_exists(USER_DB_PATH) else ""
	var out: FileAccess = FileAccess.open(USER_DB_PATH, FileAccess.WRITE)
	if out == null:
		push_error("GameDatabase: could not write DB copy to %s (%s)" % [USER_DB_PATH, error_string(FileAccess.get_open_error())])
		return USER_DB_PATH if FileAccess.file_exists(USER_DB_PATH) else ""
	out.store_buffer(bytes)
	out.close()
	# Record the source size only after a successful copy (gates against partial copies).
	_write_int(USER_DB_META_PATH, bundled_size)
	return USER_DB_PATH


func _file_size(path: String) -> int:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n: int = f.get_length()
	f.close()
	return n


func _read_int(path: String) -> int:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var line: String = f.get_line()
	f.close()
	return int(line) if line.is_valid_int() else -1


func _write_int(path: String, value: int) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_line(str(value))
		f.close()



# === Generic query ===

## Run `sql` (optionally with positional `?` bindings) and return the result
## rows as an Array of Dictionaries. Returns [] if the database is unavailable
## or the query fails. IDs are bound as parameters; SQLite's column affinity
## converts String ids to match the INTEGER key columns.
func query(sql: String, params: Array = []) -> Array:
	if not _ensure_open():
		return []
	if not _db.query_with_bindings(sql, params):
		push_warning("GameDatabase query failed: %s | %s" % [sql, _db.error_message])
		return []
	# `query_result` is held by value and is not overwritten by later queries.
	return _db.query_result


# === World map ===

## All worlds for the map dropdown. `dispOrder` is the background image filename
## (NULL for the handful of worlds with no map art -> "" so they render blank).
func get_worlds() -> Array:
	return query("SELECT worldId, worldName, COALESCE(dispOrder, '') AS dispOrder FROM WORLD ORDER BY rowid")


## A single world row (worldId, worldName, dispOrder), or {} if not found.
func get_world(world_id: String) -> Dictionary:
	var rows: Array = query(
		"SELECT worldId, worldName, COALESCE(dispOrder, '') AS dispOrder FROM WORLD WHERE worldId = ? LIMIT 1",
		[world_id]
	)
	return rows[0] if not rows.is_empty() else {}


## Lands belonging to a world (clickable regions on the world view).
func get_lands(world_id: String) -> Array:
	return query(
		"SELECT landId, landName, touchRect, labelPos FROM LAND WHERE worldId = ? ORDER BY rowid",
		[world_id]
	)


## Background-map filename (LAND.mapFiles) for a land's area view, or "" if none.
## Always a single texture, located in assets/maps/region/.
func get_land_map(world_id: String, land_id: String) -> String:
	var rows: Array = query(
		"SELECT mapFiles FROM LAND WHERE worldId = ? AND landId = ? LIMIT 1",
		[world_id, land_id]
	)
	return str(rows[0].get("mapFiles", "")).strip_edges() if not rows.is_empty() else ""


## Areas within a land (clickable regions on the area view).
func get_areas(world_id: String, land_id: String) -> Array:
	return query(
		"SELECT areaId, areaName, touchRect, labelPos FROM AREA WHERE worldId = ? AND landId = ? ORDER BY rowid",
		[world_id, land_id]
	)


## Background-map tiles for an area: { mapFiles, mapDimensions }, or {} if unknown.
## `mapFiles` is a comma-separated list of texture filenames (in assets/maps),
## `mapDimensions` is "cols:rows"; the files tile a grid in row-major order.
func get_area_map(area_id: String) -> Dictionary:
	var rows: Array = query(
		"SELECT mapFiles, mapDimensions FROM AREA WHERE areaId = ? LIMIT 1",
		[area_id]
	)
	return rows[0] if not rows.is_empty() else {}


## Town pins for an area. Mirrors the old JSON filter: drop the dummy-icon
## placeholder and event/test towns that have neither a release switch nor a
## map effect.
func get_towns(area_id: String) -> Array:
	return query(
		"SELECT townId, townName, position, iconFile FROM TOWN"
		+ " WHERE areaId = ?"
		+ " AND iconFile != 'dummy_mapicon_000.png'"
		+ " AND NOT (COALESCE(switchInfo, '') IN ('', '0') AND COALESCE(effectSwitchInfo, '') IN ('', '0'))"
		+ " ORDER BY rowid",
		[area_id]
	)


## Dungeon pins for an area. Excludes dungeon rows that are really towns: those
## reuse a town's `fileInfo` and would draw on top of the town pin.
func get_dungeons(area_id: String) -> Array:
	return query(
		"SELECT dungeonId, name, position, iconFile FROM DUNGEON"
		+ " WHERE areaId = ?"
		+ " AND (COALESCE(fileInfo, '') = '' OR fileInfo NOT IN (SELECT fileInfo FROM TOWN WHERE COALESCE(fileInfo, '') != ''))"
		+ " ORDER BY rowid",
		[area_id]
	)


## Missions for a dungeon, in intended progression order (dispOrder is INTEGER).
func get_missions(dungeon_id: String) -> Array:
	return query(
		"SELECT missionId, name, cost, exp, gil, waveCount, switchInfo FROM mission WHERE dungeonId = ? ORDER BY dispOrder",
		[dungeon_id]
	)


## Difficulty label for one mission row, or "" if unknown.
func get_mission_difficulty(mission_id: String) -> String:
	var rows: Array = query(
		"SELECT difficulty FROM mission WHERE missionId = ? LIMIT 1",
		[mission_id]
	)
	return str(rows[0].get("difficulty", "")) if not rows.is_empty() else ""


## Display name of a dungeon (DUNGEON.name), or "" if the dungeon id is unknown.
## Used to build the combat background path and the last-played-dungeon label.
func get_dungeon_name(dungeon_id: String) -> String:
	var rows: Array = query(
		"SELECT name FROM DUNGEON WHERE dungeonId = ? LIMIT 1",
		[dungeon_id]
	)
	return str(rows[0].get("name", "")) if not rows.is_empty() else ""


## A single town row (townName, iconFile) for the town scene, or {} if unknown.
## `townName` is the display name; `iconFile` ("map_icon_<digits>.png", in
## assets/map_icons) also encodes the on-disk town-data folder id.
func get_town(town_id: String) -> Dictionary:
	var rows: Array = query(
		"SELECT townName, iconFile FROM TOWN WHERE townId = ? LIMIT 1",
		[town_id]
	)
	return rows[0] if not rows.is_empty() else {}


# === Mission details (start/finish/battle data) ===
# Reconstructs the normalized mission dict that MissionService used to read from
# missions.json, but from the MISSION + CHALLENGE tables. Two indexed point
# queries per mission instead of decoding the whole 13 MB missions dataset.

# Datamine reward type codes -> the type names MissionService expects. Only LAPIS
# is granted today (and ESPER, which MissionService seeds separately); the rest
# are surfaced with their real names so the existing "unsupported reward" path
# logs something meaningful. Unknown codes fall through as their raw number.
const _REWARD_TYPE_NAMES: Dictionary = {
	"10": "UNIT", "20": "ITEM", "21": "EQUIP", "22": "MATERIA",
	"23": "KEYITEM", "27": "VISIONCARD", "50": "LAPIS", "60": "RECIPE",
}

# Mission `type` / `costType` numeric codes -> names (per the datamine).
const _MISSION_TYPE_NAMES: Dictionary = {"1": "BATTLE", "2": "EXPLORATION"}
const _COST_TYPE_NAMES: Dictionary = {"0": "NRG", "1": "Raid", "2": "Upgrade"}


## Full mission record for the start/finish/battle flow, or {} if unknown. Shape
## matches the old normalized missions.json entry that MissionService consumes:
##   { dungeon_id, name, type, wave_count, cost_type, cost, exp, gil,
##     rewards: [[TYPE, id, amount], ...], challenges: [{string, parsed, reward}] }
## (Esper first-clear rewards are not in the DB yet; MissionService overlays them.)
func get_mission(mission_id: String) -> Dictionary:
	var rows: Array = query(
		"SELECT missionId, name, dungeonId, type, costType, cost, exp, gil, waveCount, rewards"
		+ " FROM MISSION WHERE missionId = ? LIMIT 1",
		[mission_id]
	)
	if rows.is_empty():
		return {}
	var r: Dictionary = rows[0]
	return {
		"dungeon_id": int(r.get("dungeonId", 0)),
		"name": str(r.get("name", "")),
		"type": _MISSION_TYPE_NAMES.get(str(r.get("type", "1")), "BATTLE"),
		"wave_count": int(r.get("waveCount", 1)),
		"cost_type": _COST_TYPE_NAMES.get(str(r.get("costType", "0")), "NRG"),
		"cost": int(r.get("cost", 0)),
		"exp": int(r.get("exp", 0)),
		"gil": int(r.get("gil", 0)),
		"rewards": _parse_reward_list(str(r.get("rewards", ""))),
		"challenges": get_mission_challenges(mission_id),
	}


## Challenge list for a mission as { string, parsed, reward } entries (mirrors the
## old missions.json `challenges` shape). Empty if the mission has none.
func get_mission_challenges(mission_id: String) -> Array:
	var out: Array = []
	for row in query(
		"SELECT name, rewards FROM CHALLENGE WHERE missionId = ? ORDER BY challengeId",
		[mission_id]
	):
		var challenge_name: String = str(row.get("name", ""))
		var reward: Array = _parse_reward(str(row.get("rewards", "")))
		out.append({"string": challenge_name, "parsed": [challenge_name], "reward": reward})
	return out


## Parses a comma-separated reward list ("type:id:amount:rate,...") into an array
## of [TYPE_NAME, id:int, amount:int] entries. Blank/"0" -> [].
func _parse_reward_list(raw: String) -> Array:
	var out: Array = []
	if raw == "" or raw == "0":
		return out
	for chunk in raw.split(",", false):
		var reward: Array = _parse_reward(str(chunk))
		if not reward.is_empty():
			out.append(reward)
	return out


## Parses a single "type:id:amount[:rate]" reward token into [TYPE_NAME, id, amount].
## Unknown type codes pass through as their raw number string. Returns [] if blank.
func _parse_reward(raw: String) -> Array:
	if raw == "" or raw == "0":
		return []
	var parts: PackedStringArray = raw.split(":")
	if parts.is_empty():
		return []
	var type_name: String = _REWARD_TYPE_NAMES.get(str(parts[0]), str(parts[0]))
	var id_val: int = int(parts[1]) if parts.size() > 1 else 0
	var amount: int = int(parts[2]) if parts.size() > 2 else 1
	return [type_name, id_val, amount]


## World-map location of a single mission: { worldId, landId, areaId, dungeonId,
## dungeonPosition }, or {} if the mission id is unknown. Used to deep-link the
## world map straight to the area a mission lives in (and to pan to its dungeon).
## `dungeonPosition` is the dungeon's "x:y" pin coordinate ("" if the dungeon row
## is missing).
func get_mission_location(mission_id: String) -> Dictionary:
	var rows: Array = query(
		"SELECT m.worldId, m.landId, m.areaId, m.dungeonId, COALESCE(d.position, '') AS dungeonPosition"
		+ " FROM MISSION m LEFT JOIN DUNGEON d ON d.dungeonId = m.dungeonId"
		+ " WHERE m.missionId = ? LIMIT 1",
		[mission_id]
	)
	return rows[0] if not rows.is_empty() else {}


# === Combat / encounters ===
# Per-mission encounter resolution. Each query reads only the handful of rows a
# single mission/formation needs (all four tables are indexed on these keys), so
# combat entry no longer decodes the whole MISSION_PHASE / BATTLE_GROUP /
# MONSTER_PARTS datasets up front. See features/battle/logic/encounter_resolver.gd.

## Ordered base battle phases for a mission (the wave sequence). A phase counts
## as a battle wave when it is NOT switch-gated (switchInfo empty) AND it either
## carries a battle background (battleBgId != 0) OR its targetId resolves to a
## real formation — a BATTLE_LOTTERY pool (weight > 0) or a direct BATTLE_GROUP.
## This mirrors the datamine's `is_battle_phase`: many real waves carry
## battleBgId 0 but still point at a valid pool/group, and filtering those out
## left whole missions with no enemies. Cutscene phases (battleBgId 0 + a
## targetId that resolves to nothing) are correctly excluded. Each row:
## phaseNum, targetId.
func get_mission_phases(mission_id: String) -> Array:
	return query(
		"SELECT p.phaseNum, p.targetId FROM MISSION_PHASE p"
		+ " WHERE p.missionId = ? AND COALESCE(p.switchInfo, '') = ''"
		+ " AND ( p.battleBgId != 0"
		+ "   OR EXISTS (SELECT 1 FROM BATTLE_LOTTERY l WHERE l.poolId = p.targetId AND l.weight > 0)"
		+ "   OR EXISTS (SELECT 1 FROM BATTLE_GROUP g WHERE g.battleGroupId = p.targetId) )"
		+ " ORDER BY p.phaseNum",
		[mission_id]
	)


## Weighted formation pool for a lottery poolId: rows of battleGroupId, weight
## (positive weights only). Empty if the id is not a lottery pool.
func get_lottery_pool(pool_id: String) -> Array:
	return query(
		"SELECT battleGroupId, weight FROM BATTLE_LOTTERY WHERE poolId = ? AND weight > 0",
		[pool_id]
	)


## True if the id is itself a concrete battle group (as opposed to a lottery pool).
func has_battle_group(battle_group_id: String) -> bool:
	return not query(
		"SELECT 1 FROM BATTLE_GROUP WHERE battleGroupId = ? LIMIT 1",
		[battle_group_id]
	).is_empty()


## Monster slots for a battle group, ordered by dispOrder. Each row: monsterId,
## dispPos ("x,y"), initialDisp (0 = reinforcement, not initially shown).
func get_battle_group(battle_group_id: String) -> Array:
	return query(
		"SELECT monsterId, dispPos, initialDisp FROM BATTLE_GROUP WHERE battleGroupId = ? ORDER BY dispOrder",
		[battle_group_id]
	)


## Main-body parts row (lowest partsNum) for a 9-digit monsterId, or {}. Carries
## the per-instance combat stats, the elemental resist / drop columns, plus the
## dictionaryId/name used for sprites and the display name.
func get_monster_parts(monster_id: String) -> Dictionary:
	var rows: Array = query(
		"SELECT hp, mp, atk, def, intl, mnd, level, exp, gil, dictionaryId, name,"
		+ " elemResistValue, dropInfo"
		+ " FROM MONSTER_PARTS WHERE monsterId = ? ORDER BY partsNum LIMIT 1",
		[monster_id]
	)
	return rows[0] if not rows.is_empty() else {}


## Canonical display name for a 7-digit dictionaryId from MONSTER_DICTIONARY, or
## "" if absent. This is the datamine's monsterId -> dictionaryId -> name path.
func get_monster_name(dictionary_id: String) -> String:
	var rows: Array = query(
		"SELECT name FROM MONSTER_DICTIONARY WHERE dictionaryId = ? LIMIT 1",
		[dictionary_id]
	)
	return str(rows[0].get("name", "")) if not rows.is_empty() else ""


## Scenario (boss/story) battle groups for a mission, in wave order. Missions with
## no MISSION_PHASE resolve their waves through the scenario chain:
##   LOCATION_SCENARIO_BATTLE (locationType 1, targetId == missionId)
##     -> scenarioBattleInfo (comma-separated scenarioBattleIds, kept in order)
##     -> SCENARIO_BATTLE.battleGroupId (one guaranteed formation per scenario)
## Returns the ordered battleGroupId list (each is one boss/story wave). Empty if
## the mission has no scenario battles. Scenario rows with no battle group are skipped.
func get_mission_scenario_groups(mission_id: String) -> Array:
	var battle_groups: Array = []
	for loc in query(
		"SELECT scenarioBattleInfo FROM LOCATION_SCENARIO_BATTLE WHERE locationType = 1 AND targetId = ?",
		[mission_id]
	):
		for piece in str(loc.get("scenarioBattleInfo", "")).split(",", false):
			var scenario_id: String = str(piece)
			if scenario_id == "":
				continue
			var sb: Array = query(
				"SELECT COALESCE(battleGroupId, '') AS battleGroupId FROM SCENARIO_BATTLE WHERE scenarioBattleId = ? LIMIT 1",
				[scenario_id]
			)
			if sb.is_empty():
				continue
			var bg: String = str(sb[0].get("battleGroupId", ""))
			if bg != "" and bg != "0":
				battle_groups.append(bg)
	return battle_groups
