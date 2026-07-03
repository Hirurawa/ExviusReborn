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
# Sidecar recording the MD5 hash of the bundled DB the user copy was made from,
# so a re-exported/updated database is detected and re-copied.
const USER_DB_META_PATH: String = "user://ffbe-data.db.meta"

var _db: SQLite = null
var _open_failed: bool = false

# Lazily-loaded magic-skill caches (see has_magic / get_magic): the small set of
# all magicIds for existence checks, and per-id reconstructed skill records.
var _magic_id_set: Dictionary = {}
var _magic_id_set_loaded: bool = false
var _magic_cache: Dictionary = {}

# Lazily-loaded ability caches (active + passive share the `ability` table, split
# by abilityType): id -> "ability"/"passive" kind map, plus per-id records.
var _ability_kind_map: Dictionary = {}
var _ability_kind_loaded: bool = false
var _ability_cache: Dictionary = {}
var _passive_cache: Dictionary = {}
var _limitburst_cache: Dictionary = {}
var _item_cache: Dictionary = {}
var _equipment_cache: Dictionary = {}


# === Connection ===

func preload_database() -> void:
	_ensure_local_db()

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
## whenever the bundled DB's change signature (MD5 hash)
## differs from the one recorded at copy time, so an edited or re-exported database
## is picked up automatically.
func _ensure_local_db() -> String:
	if not FileAccess.file_exists(BUNDLED_DB_PATH):
		# Bundled DB unreadable — fall back to an existing copy if we have one.
		return USER_DB_PATH if FileAccess.file_exists(USER_DB_PATH) else ""

	var signature: String = FileAccess.get_md5(BUNDLED_DB_PATH)
	if signature == "":
		return USER_DB_PATH if FileAccess.file_exists(USER_DB_PATH) else ""

	if FileAccess.file_exists(USER_DB_PATH) and _read_text(USER_DB_META_PATH) == signature:
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
	# Record the source signature only after a successful copy (gates against partial copies).
	_write_text(USER_DB_META_PATH, signature)
	return USER_DB_PATH


func _read_text(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var line: String = f.get_line()
	f.close()
	return line


func _write_text(path: String, value: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_line(value)
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

## All worlds for the map dropdown. The returned `dispOrder` key carries the
## background image filename (world.imageInfo; NULL for the handful of worlds
## with no map art -> "" so they render blank). The result keys (worldName,
## dispOrder) are aliases kept stable for the map UI consumer.
func get_worlds() -> Array:
	return query("SELECT worldId, name AS worldName, COALESCE(imageInfo, '') AS dispOrder, switchInfo FROM world ORDER BY rowid")


## A single world row (worldId, worldName, dispOrder), or {} if not found.
## `dispOrder` is the background image filename (world.imageInfo), aliased.
func get_world(world_id: String) -> Dictionary:
	var rows: Array = query(
		"SELECT worldId, name AS worldName, COALESCE(imageInfo, '') AS dispOrder, switchInfo FROM world WHERE worldId = ? LIMIT 1",
		[world_id]
	)
	return rows[0] if not rows.is_empty() else {}


## Lands belonging to a world (clickable regions on the world view).
func get_lands(world_id: String) -> Array:
	return query(
		"SELECT landId, name AS landName, touchRect, labelPos, switchInfo FROM land WHERE worldId = ? ORDER BY rowid",
		[world_id]
	)


## Background-map filename (land.imageInfo) for a land's area view, or "" if none.
## Always a single texture, located in assets/maps/region/. The returned key is
## aliased to `mapFiles` for the map UI consumer.
func get_land_map(world_id: String, land_id: String) -> String:
	var rows: Array = query(
		"SELECT imageInfo AS mapFiles FROM land WHERE worldId = ? AND landId = ? LIMIT 1",
		[world_id, land_id]
	)
	return str(rows[0].get("mapFiles", "")).strip_edges() if not rows.is_empty() else ""


## Areas within a land (clickable regions on the area view).
func get_areas(world_id: String, land_id: String) -> Array:
	return query(
		"SELECT areaId, name AS areaName, touchRect, labelPos, switchInfo FROM area WHERE worldId = ? AND landId = ? ORDER BY rowid",
		[world_id, land_id]
	)


## Background-map tiles for an area: { mapFiles, mapDimensions }, or {} if unknown.
## `mapFiles` (area.imageInfo) is a comma-separated list of texture filenames (in
## assets/maps), `mapDimensions` (area.mapDimension) is "cols:rows"; the files
## tile a grid in row-major order. Both result keys are aliases kept stable for
## the map UI consumer.
func get_area_map(area_id: String) -> Dictionary:
	var rows: Array = query(
		"SELECT imageInfo AS mapFiles, mapDimension AS mapDimensions FROM area WHERE areaId = ? LIMIT 1",
		[area_id]
	)
	return rows[0] if not rows.is_empty() else {}


## Town pins for an area. Every town in the area is returned (no filtering).
## `iconFile` is resolved through the icon master (town.iconId -> icon.iconFile)
## and aliased so the map UI consumer keeps reading the same key.
func get_towns(area_id: String) -> Array:
	return query(
		"SELECT t.townId, t.name AS townName, t.position, COALESCE(i.iconFile, '') AS iconFile, t.switchInfo FROM town t"
		+ " LEFT JOIN icon i ON i.iconId = t.iconId"
		+ " WHERE t.areaId = ?"
		+ " ORDER BY t.rowid",
		[area_id]
	)


## Dungeon pins for an area. Excludes dungeon rows that are really towns: those
## reuse a town's `fileInfo` and would draw on top of the town pin. `iconFile` is
## resolved through the icon master (dungeon.iconId -> icon.iconFile) and aliased.
func get_dungeons(area_id: String) -> Array:
	return query(
		"SELECT d.dungeonId, d.name, d.position, COALESCE(i.iconFile, '') AS iconFile, d.switchInfo FROM dungeon d"
		+ " LEFT JOIN icon i ON i.iconId = d.iconId"
		+ " WHERE d.areaId = ?"
		+ " AND (COALESCE(d.fileInfo, '') = '' OR d.fileInfo NOT IN (SELECT fileInfo FROM town WHERE COALESCE(fileInfo, '') != ''))"
		+ " ORDER BY d.rowid",
		[area_id]
	)


## Missions for a dungeon, in intended progression order (dispOrder is INTEGER).
func get_missions(dungeon_id: String) -> Array:
	return query(
		"SELECT missionId, name, cost, exp, gil, waveCount, switchInfo FROM mission WHERE dungeonId = ? ORDER BY dispOrder",
		[dungeon_id]
	)


## Display name of a dungeon (dungeon.name), or "" if the dungeon id is unknown.
## Used to build the combat background path and the last-played-dungeon label.
func get_dungeon_name(dungeon_id: String) -> String:
	var rows: Array = query(
		"SELECT name FROM dungeon WHERE dungeonId = ? LIMIT 1",
		[dungeon_id]
	)
	return str(rows[0].get("name", "")) if not rows.is_empty() else ""


## A single town row (townName, iconFile) for the town scene, or {} if unknown.
## `townName` is the display name; `iconFile` ("map_icon_<digits>.png", in
## assets/map_icons, resolved via town.iconId -> icon.iconFile) also encodes the
## on-disk town-data folder id.
func get_town_stores(town_id: String) -> Array:
	return query(
		"SELECT * FROM town_store WHERE townId = ? AND storeType = 1 ORDER BY storeId",
		[town_id]
	)


func get_store_items(store_id: String) -> Array:
	return query(
		"SELECT * FROM store_item WHERE storeId = ? ORDER BY storeItemId",
		[store_id]
	)


func get_town(town_id: String) -> Dictionary:
	var rows: Array = query(
		"SELECT t.name AS townName, COALESCE(i.iconFile, '') AS iconFile, COALESCE(t.openSwitch, '') AS openSwitch FROM town t"
		+ " LEFT JOIN icon i ON i.iconId = t.iconId"
		+ " WHERE t.townId = ? LIMIT 1",
		[town_id]
	)
	return rows[0] if not rows.is_empty() else {}


func get_quests_for_town(town_id: String) -> Array:
	return query(
		"SELECT q.questId, q.name AS questName, q.switchInfo, q.reward, q.openSwitch, qs.questSubId, qs.task, qs.targetType, qs.targetParam"
		+ " FROM quest q"
		+ " LEFT JOIN quest_sub qs ON q.questId = qs.questId"
		+ " WHERE q.locationType = 2 AND q.locationId = ?"
		+ " ORDER BY q.questId, qs.dispOrder",
		[town_id]
	)


# === Mission details (start/finish/battle data) ===
# Reconstructs the normalized mission dict that MissionService used to read from
# missions.json, but from the mission + challenge tables. Two indexed point
# queries per mission instead of decoding the whole 13 MB missions dataset.

# Datamine reward type codes -> the type names MissionService expects. Only LAPIS
# is granted today (and ESPER, which MissionService seeds separately); the rest
# are surfaced with their real names so the existing "unsupported reward" path
# logs something meaningful. Unknown codes fall through as their raw number.
const _REWARD_TYPE_NAMES: Dictionary = {
	"10": "UNIT", "20": "ITEM", "21": "EQUIP", "22": "MATERIA",
	"23": "KEYITEM", "27": "VISIONCARD", "50": "LAPIS", "60": "RECIPE",
}

# Mission `type` numeric codes -> names (per the datamine).
const _MISSION_TYPE_NAMES: Dictionary = {"1": "BATTLE", "2": "EXPLORATION"}


## Full mission record for the start/finish/battle flow, or {} if unknown. Shape
## matches the old normalized missions.json entry that MissionService consumes:
##   { dungeon_id, name, type, wave_count, cost_type, cost, exp, gil,
##     rewards: [[TYPE, id, amount], ...], challenges: [{string, parsed, reward}] }
## The curated DB is main-story only (no Raid/Upgrade missions), so cost_type is
## always "NRG". (Esper first-clear rewards are not in the DB yet; MissionService
## overlays them.)
func get_mission(mission_id: String) -> Dictionary:
	var rows: Array = query(
		"SELECT missionId, name, dungeonId, type, cost, exp, gil, waveCount, rewards, openSwitch"
		+ " FROM mission WHERE missionId = ? LIMIT 1",
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
		"cost_type": "NRG",
		"cost": int(r.get("cost", 0)),
		"exp": int(r.get("exp", 0)),
		"gil": int(r.get("gil", 0)),
		"rewards": _parse_reward_list(str(r.get("rewards", ""))),
		"challenges": get_mission_challenges(mission_id),
		"open_switches": str(r.get("openSwitch", "")),
	}


## Challenge list for a mission as { string, parsed, reward } entries (mirrors the
## old missions.json `challenges` shape). Empty if the mission has none. The
## reward column is challenge.rewardInfo, aliased to `rewards`.
func get_mission_challenges(mission_id: String) -> Array:
	var out: Array = []
	for row in query(
		"SELECT name, rewardInfo AS rewards FROM challenge WHERE missionId = ? ORDER BY challengeId",
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
		+ " FROM mission m LEFT JOIN dungeon d ON d.dungeonId = m.dungeonId"
		+ " WHERE m.missionId = ? LIMIT 1",
		[mission_id]
	)
	return rows[0] if not rows.is_empty() else {}


# === Combat / encounters ===
# Per-mission encounter resolution. Each query reads only the handful of rows a
# single mission/formation needs (all four tables are indexed on these keys), so
# combat entry no longer decodes the whole mission_phase / battle_group /
# monster_parts datasets up front. See features/battle/logic/encounter_resolver.gd.

## Ordered base battle phases for a mission (the wave sequence). A phase counts
## as a battle wave when it is NOT switch-gated (switchInfo empty) AND it either
## carries a battle background (battleBgId != 0) OR its targetId resolves to a
## real formation — a battle_lottery pool (weight > 0) or a direct battle_group.
## This mirrors the datamine's `is_battle_phase`: many real waves carry
## battleBgId 0 but still point at a valid pool/group, and filtering those out
## left whole missions with no enemies. Cutscene phases (battleBgId 0 + a
## targetId that resolves to nothing) are correctly excluded. Each row:
## phaseNum, targetId.
func get_mission_phases(mission_id: String) -> Array:
	return query(
		"SELECT p.phaseNum, p.targetId FROM mission_phase p"
		+ " WHERE p.missionId = ? AND COALESCE(p.switchInfo, '') = ''"
		+ " AND ( p.battleBgId != 0"
		+ "   OR EXISTS (SELECT 1 FROM battle_lottery l WHERE l.poolId = p.targetId AND l.weight > 0)"
		+ "   OR EXISTS (SELECT 1 FROM battle_group g WHERE g.battleGroupId = p.targetId) )"
		+ " ORDER BY p.phaseNum",
		[mission_id]
	)


## Weighted formation pool for a lottery poolId: rows of battleGroupId, weight
## (positive weights only). Empty if the id is not a lottery pool.
func get_lottery_pool(pool_id: String) -> Array:
	return query(
		"SELECT battleGroupId, weight FROM battle_lottery WHERE poolId = ? AND weight > 0",
		[pool_id]
	)


## True if the id is itself a concrete battle group (as opposed to a lottery pool).
func has_battle_group(battle_group_id: String) -> bool:
	return not query(
		"SELECT 1 FROM battle_group WHERE battleGroupId = ? LIMIT 1",
		[battle_group_id]
	).is_empty()


## Monster slots for a battle group, ordered by dispOrder. Each row: monsterId,
## dispPos ("x,y"), initialDisp (0 = reinforcement, not initially shown).
func get_battle_group(battle_group_id: String) -> Array:
	return query(
		"SELECT monsterId, dispPos, initialDisp FROM battle_group WHERE battleGroupId = ? ORDER BY dispOrder",
		[battle_group_id]
	)


## Main-body parts row (lowest partsNum) for a 9-digit monsterId, or {}. Carries
## the per-instance combat stats, the elemental resist / drop columns, plus the
## dictionaryId (from the monster master) and the per-variant name used for the
## sprite and the display-name fallback. The datamine's mag/spr stats and the JP
## monsterName are aliased to the in-game `intl`/`mnd`/`name` keys the encounter
## resolver expects.
func get_monster_parts(monster_id: String) -> Dictionary:
	var rows: Array = query(
		"SELECT p.hp, p.mp, p.atk, p.def, p.mag AS intl, p.spr AS mnd, p.level, p.exp, p.gil,"
		+ " m.dictionaryId AS dictionaryId, p.monsterName AS name,"
		+ " p.elemResistValue, p.dropInfo"
		+ " FROM monster_parts p LEFT JOIN monster m ON m.monsterId = p.monsterId"
		+ " WHERE p.monsterId = ? ORDER BY p.partsNum LIMIT 1",
		[monster_id]
	)
	return rows[0] if not rows.is_empty() else {}


## Canonical display name for a 7-digit dictionaryId from monster_dictionary, or
## "" if absent. This is the datamine's monsterId -> dictionaryId -> name path.
func get_monster_name(dictionary_id: String) -> String:
	var rows: Array = query(
		"SELECT name FROM monster_dictionary WHERE dictionaryId = ? LIMIT 1",
		[dictionary_id]
	)
	return str(rows[0].get("name", "")) if not rows.is_empty() else ""


## Scenario (boss/story) battle groups for a mission, in wave order. Missions with
## no mission_phase resolve their waves through the scenario chain:
##   location_scenario_battle (locationType 1, targetId == missionId)
##     -> scenarioBattleInfo (comma-separated scenarioBattleIds, kept in order)
##     -> scenario_battle_group.battleGroupId (one guaranteed formation per scenario)
## Returns the ordered battleGroupId list (each is one boss/story wave). Empty if
## the mission has no scenario battles. Scenario rows with no battle group are skipped.
func get_mission_scenario_groups(mission_id: String) -> Array:
	var battle_groups: Array = []
	for loc in query(
		"SELECT scenarioBattleInfo FROM location_scenario_battle WHERE locationType = 1 AND targetId = ?",
		[mission_id]
	):
		for piece in str(loc.get("scenarioBattleInfo", "")).split(",", false):
			var scenario_id: String = str(piece)
			if scenario_id == "":
				continue
			var sb: Array = query(
				"SELECT COALESCE(battleGroupId, '') AS battleGroupId FROM scenario_battle_group WHERE scenarioBattleId = ? LIMIT 1",
				[scenario_id]
			)
			if sb.is_empty():
				continue
			var bg: String = str(sb[0].get("battleGroupId", ""))
			if bg != "" and bg != "0":
				battle_groups.append(bg)
	return battle_groups


# === Unit progression ===

## Per-level XP rows for a unit exp pattern, ordered by level. Each row:
## { level, needExp }. `needExp` at level L is the cumulative XP required to
## REACH level L (the table carries an L=1=0 row); callers convert this to the
## marginal XP per level as needed. Empty if the pattern id is unknown.
func get_unit_exp_pattern(pattern_id: int) -> Array:
	return query(
		"SELECT level, needExp FROM unit_exp_pattern WHERE expPatternId = ? ORDER BY level",
		[pattern_id]
	)


## All per-level XP rows across all unit exp patterns, ordered by pattern id then level.
## Each row: { expPatternId, level, needExp }.
func get_all_unit_exp_patterns() -> Array:
	return query("SELECT expPatternId, level, needExp FROM unit_exp_pattern ORDER BY expPatternId, level")


func get_summonable_units() -> Array:
	var val = query("select unitId, unitName, min(rare) as minRare from unit where isSummonable is 1 and rare is not 7 and unitName  NOT GLOB '*[ぁ-んァ-ヶ一-龠々]*' GROUP by unitSeries")
	return val

func get_all_units() -> Array:
	var val: Array = query("SELECT * FROM unit")
	return val

func get_unit(unit_id: int) -> Dictionary:
	var rows: Array = query("SELECT * FROM unit WHERE unitId = ? LIMIT 1", [unit_id])
	return rows[0] if not rows.is_empty() else {}

func get_unit_class_up_info(unit_id: int) -> Dictionary:
	var rows: Array = query("select classUpUnitID, gil, materialInfo from unit_class_up where unitId = ? LIMIT 1", [unit_id])
	return rows[0] if not rows.is_empty() else {}

func get_unit_class_up(unit_id: int) -> Array:
	var rows: Array = query("select * from unit where unitId = (select classUpUnitID from unit_class_up where unitId = ?) limit 1", [unit_id])
	return rows[0] if not rows.is_empty() else {}

func get_unit_skills(unit_series_id: int, rarity: int, level: int) -> Array:
	return query("SELECT * from unit_series_lv_acquire where unitSeriesId = ? AND (rarity < ? OR (rarity = ? AND level <= ?)) order by rarity, level", [unit_series_id, rarity, rarity, level])

func get_unit_max_rarity(unit_series_id: int) -> int:
	var rows: Array = query("select max(rare) from unit where unitSeries = ? limit 1", [unit_series_id])
	return rows[0].get("max(rare)", 0)

func get_unit_next_rarity(unit_id: int) -> Dictionary:
	var rows: Array = query("select u.* from unit u where u.unitId = (select classUpUnitID  from unit_class_up ucu where ucu.unitId = ?)", [unit_id])
	return rows[0] if not rows.is_empty() else {}

# === Skills: magic ===

const _MAGIC_TYPE_NAMES: Dictionary = {"1": "White", "2": "Black", "3": "Green", "4": "Blue"}
# Fixed slot order of the magic.element column (8 comma-separated values).
const _MAGIC_ELEMENTS: Array = ["Fire", "Ice", "Lightning", "Water", "Wind", "Earth", "Light", "Dark"]


## True if `magic_id` is a magic skill. Backed by a lazily-loaded set of the
## ~491 magicIds, so repeated existence checks (skill classification, combat
## animation selection) cost a single dictionary lookup — no per-call query and
## no dataset decode. Only latches once a load actually returns rows, so a call
## made before the DB is ready (e.g. early login hydration) retries later instead
## of leaving the set permanently empty.
func has_magic(magic_id) -> bool:
	if not _magic_id_set_loaded:
		var rows: Array = query("SELECT magicId FROM magic")
		if not rows.is_empty():
			for row in rows:
				_magic_id_set[str(row.get("magicId", ""))] = true
			_magic_id_set_loaded = true
	return _magic_id_set.has(str(magic_id))


## Full magic-skill record reconstructed from the magic (+ icon + magic_explain)
## tables, matching the shape skills_magic.json used to provide, or {} if unknown.
## Cached per id (bounded by the 491-row master) so repeated combat resolves / UI
## builds of the same skill don't re-query or re-decode.
func get_magic(magic_id) -> Dictionary:
	var key: String = str(magic_id)
	if _magic_cache.has(key):
		return _magic_cache[key]
	var rows: Array = query(
		"SELECT m.*, COALESCE(i.iconFile, '') AS iconFile, COALESCE(e.explainShort, '') AS explainShort"
		+ " FROM magic m"
		+ " LEFT JOIN icon i ON i.iconId = m.iconId"
		+ " LEFT JOIN magic_explain e ON e.magicId = m.magicId"
		+ " WHERE m.magicId = ? LIMIT 1",
		[key]
	)
	if rows.is_empty():
		return {}
	var built: Dictionary = _build_magic_record(rows[0])
	_magic_cache[key] = built
	return built


## Reconstructs the skills_magic.json record from a joined magic row. The datamine
## packs per-effect and per-frame data into delimited strings; see the decoders
## below for the grammar. `description` uses magic_explain.explainShort (the rich
## per-effect English text the old JSON carried is not in the DB).
func _build_magic_record(row: Dictionary) -> Dictionary:
	var attack_frames: Array = []
	var attack_damage: Array = []
	var attack_count: Array = []
	_decode_attack_frames(str(row.get("attackFrames", "")), attack_frames, attack_damage, attack_count)
	var cost_val: int = int(row.get("cost", 0))
	return {
		"name": str(row.get("name", "")),
		"icon": str(row.get("iconFile", "")),
		"compendium_id": int(row.get("dispOrder", 0)),
		"rarity": int(row.get("rarity", 0)),
		"cost": {"MP": cost_val} if cost_val > 0 else {},
		"magic_type": _MAGIC_TYPE_NAMES.get(str(row.get("magicType", "")), ""),
		"attack_count": attack_count,
		"attack_damage": attack_damage,
		"attack_frames": attack_frames,
		"effect_frames": _decode_effect_frames(str(row.get("effectFrames", ""))),
		"element_inflict": _decode_element_inflict(str(row.get("element", ""))),
		"effects_raw": _decode_effects_raw(row),
		"description": str(row.get("explainShort", "")),
	}


# === Skills: abilities (active + passive) ===
# Active abilities (skills_ability.json) and passives (skills_passive.json) both
# live in the `ability` table, split by abilityType (2 = active, 1 = passive).

## "ability" (active, abilityType 2), "passive" (abilityType 1), or "" if the id
## isn't in the ability master. Backed by a lazily-loaded id -> kind map so the
## repeated skill-classification checks don't re-query or decode anything. Only
## latches once a load actually returns rows, so a call made before the DB is
## ready (e.g. early login hydration) retries later instead of leaving the map
## permanently empty.
func ability_kind(ability_id) -> String:
	if not _ability_kind_loaded:
		var rows: Array = query("SELECT abilityId, abilityType FROM ability")
		if not rows.is_empty():
			for row in rows:
				var kind: String = "ability" if int(row.get("abilityType", 0)) == 2 else "passive"
				_ability_kind_map[str(row.get("abilityId", ""))] = kind
			_ability_kind_loaded = true
	return _ability_kind_map.get(str(ability_id), "")


## True if the id is an active ability (abilityType 2).
func has_ability(ability_id) -> bool:
	return ability_kind(ability_id) == "ability"


## True if the id is a passive (abilityType 1).
func has_passive(ability_id) -> bool:
	return ability_kind(ability_id) == "passive"


## Full active-ability record (abilityType 2) reconstructed from the ability
## (+ icon + ability_explain) tables, matching skills_ability.json's shape, or {}
## if the id is not an active ability. Cached per id.
func get_ability(ability_id) -> Dictionary:
	var key: String = str(ability_id)
	if _ability_cache.has(key):
		return _ability_cache[key]
	var rows: Array = query(
		"SELECT a.*, COALESCE(i.iconFile, '') AS iconFile, COALESCE(e.explainShort, '') AS explainShort"
		+ " FROM ability a"
		+ " LEFT JOIN icon i ON i.iconId = a.iconId"
		+ " LEFT JOIN ability_explain e ON e.abilityId = a.abilityId"
		+ " WHERE a.abilityId = ? AND a.abilityType = 2 LIMIT 1",
		[key]
	)
	if rows.is_empty():
		return {}
	var built: Dictionary = _build_ability_record(rows[0])
	_ability_cache[key] = built
	return built


## Full passive record (abilityType 1) reconstructed from the ability (+ icon +
## ability_explain) tables, matching skills_passive.json's shape, or {} if the id
## is not a passive. Cached per id.
func get_passive(ability_id) -> Dictionary:
	var key: String = str(ability_id)
	if _passive_cache.has(key):
		return _passive_cache[key]
	var rows: Array = query(
		"SELECT a.*, COALESCE(i.iconFile, '') AS iconFile, COALESCE(e.explainShort, '') AS explainShort"
		+ " FROM ability a"
		+ " LEFT JOIN icon i ON i.iconId = a.iconId"
		+ " LEFT JOIN ability_explain e ON e.abilityId = a.abilityId"
		+ " WHERE a.abilityId = ? AND a.abilityType = 1 LIMIT 1",
		[key]
	)
	if rows.is_empty():
		return {}
	var built: Dictionary = _build_passive_record(rows[0])
	_passive_cache[key] = built
	return built


## Reconstructs the skills_ability.json record (active ability) from a joined row.
## Shares the magic decoders; `description` uses ability_explain.explainShort.
func _build_ability_record(row: Dictionary) -> Dictionary:
	var attack_frames: Array = []
	var attack_damage: Array = []
	var attack_count: Array = []
	_decode_attack_frames(str(row.get("attackFrames", "")), attack_frames, attack_damage, attack_count)
	var cost_val: int = int(row.get("cost", 0))
	return {
		"name": str(row.get("name", "")),
		"icon": str(row.get("iconFile", "")),
		"compendium_id": int(row.get("dispOrder", 0)),
		"rarity": int(row.get("rarity", 0)),
		"cost": {"MP": cost_val} if cost_val > 0 else {},
		"attack_count": attack_count,
		"attack_damage": attack_damage,
		"attack_frames": attack_frames,
		"effect_frames": _decode_effect_frames(str(row.get("effectFrames", ""))),
		"move_type": int(row.get("moveType", 0)),
		"motion_type": int(row.get("motionType", 0)),
		"element_inflict": _decode_element_inflict(str(row.get("element", ""))),
		"effects_raw": _decode_effects_raw(row),
		"description": str(row.get("explainShort", "")),
	}


## Reconstructs the skills_passive.json record (passive) from a joined row.
func _build_passive_record(row: Dictionary) -> Dictionary:
	return {
		"name": str(row.get("name", "")),
		"icon": str(row.get("iconFile", "")),
		"compendium_id": int(row.get("dispOrder", 0)),
		"rarity": int(row.get("rarity", 0)),
		"element_inflict": _decode_element_inflict(str(row.get("element", ""))),
		"effects_raw": _decode_effects_raw(row),
		"description": str(row.get("explainShort", "")),
	}


# === Skills: limit bursts ===

## Full limit-burst record reconstructed from the limitburst (+ limitburst_lv)
## tables, matching the shape limitbursts.json used to provide, or {} if unknown.
## Cached per id. Limit bursts level up: `levels[i]` is [gauge, effects_raw] for
## level i (gauge = limitburst_lv.cost / 100), and the top-level `effects_raw`
## mirrors level 0 (what the skill resolver / combat reads). Per-level params come
## from limitburst_lv; target/targetRange/processId are shared on the limitburst row.
func get_limitburst(limitburst_id) -> Dictionary:
	var key: String = str(limitburst_id)
	if _limitburst_cache.has(key):
		return _limitburst_cache[key]
	var rows: Array = query("SELECT * FROM limitburst WHERE limitBurstId = ? LIMIT 1", [key])
	if rows.is_empty():
		return {}
	var lv_rows: Array = query(
		"SELECT cost, processParam FROM limitburst_lv WHERE limitBurstId = ? ORDER BY lv",
		[key]
	)
	var built: Dictionary = _build_limitburst_record(rows[0], lv_rows)
	_limitburst_cache[key] = built
	return built


func _build_limitburst_record(row: Dictionary, lv_rows: Array) -> Dictionary:
	var attack_frames: Array = []
	var attack_damage: Array = []
	var attack_count: Array = []
	_decode_attack_frames(str(row.get("attackFrames", "")), attack_frames, attack_damage, attack_count)

	var target_raw: String = str(row.get("target", ""))
	var range_raw: String = str(row.get("targetRange", ""))
	var proc_raw: String = str(row.get("processId", ""))
	var proc_groups: int = _group_count(proc_raw)
	var levels: Array = []
	for lv_row in lv_rows:
		var level_param: String = str(lv_row.get("processParam", ""))
		# A level's processParam can carry MORE effect groups than the base
		# processId (extra effects broadcast the row's last target/range/process).
		var n: int = maxi(proc_groups, _group_count(level_param)) if proc_raw != "" else _group_count(target_raw)
		levels.append([
			_limitburst_gauge(int(lv_row.get("cost", 0))),
			_build_effects_raw(n, target_raw, range_raw, proc_raw, level_param),
		])

	return {
		"name": str(row.get("name", "")),
		"cost": 0,
		"attack_count": attack_count,
		"attack_damage": attack_damage,
		"attack_frames": attack_frames,
		"effect_frames": _decode_effect_frames(str(row.get("effectFrame", ""))),
		"element_inflict": _decode_element_inflict(str(row.get("element", ""))),
		"levels": levels,
		"effects_raw": levels[0][1] if not levels.is_empty() else [],
		"description": str(row.get("description", "")),
	}


## Limit-burst gauge for a limitburst_lv.cost: cost / 100, as an int when whole
## (matching the old JSON) or a float otherwise.
func _limitburst_gauge(cost: int) -> Variant:
	if cost % 100 == 0:
		return cost / 100
	return cost / 100.0


# === Items ===

const _ITEM_TYPE_NAMES: Dictionary = {"1": "Consumable", "2": "Item", "3": "Awakening"}

const _EQUIP_SLOT_NAMES: Dictionary = {
	"1": "Weapon",
	"2": "Shield",
	"3": "Headgear",
	"4": "Chest",
	"5": "Accessory",
}

const _EQUIP_TYPE_NAMES: Dictionary = {
	"1": "Short Sword",
	"2": "Sword",
	"3": "Great Sword",
	"4": "Katana",
	"5": "Staff",
	"6": "Rod",
	"7": "Bow",
	"8": "Axe",
	"9": "Hammer",
	"10": "Spear",
	"11": "Instrument",
	"12": "Whip",
	"13": "Throwing Weapon",
	"14": "Gun",
	"15": "Mace",
	"16": "Fist Weapon",
	"30": "Light Shield",
	"31": "Heavy Shield",
	"40": "Hat",
	"41": "Helm",
	"50": "Cloth Armor",
	"51": "Light Armor",
	"52": "Heavy Armor",
	"53": "Robe",
	"60": "Accessory",
}

const _EQUIP_TYPE_ICONS: Dictionary = {
	"1": "dagger.png",
	"2": "sword.png",
	"3": "greatSword.png",
	"4": "katana.png",
	"5": "staff.png",
	"6": "rod.png",
	"7": "bow.png",
	"8": "axe.png",
	"9": "hammer.png",
	"10": "spear.png",
	"11": "harp.png",
	"12": "whip.png",
	"13": "throwing.png",
	"14": "gun.png",
	"15": "mace.png",
	"16": "fist.png",
	"30": "lightShield.png",
	"31": "heavyShield.png",
	"40": "hat.png",
	"41": "helm.png",
	"50": "clothes.png",
	"51": "lightArmor.png",
	"52": "heavyArmor.png",
	"53": "robe.png",
	"60": "accessory.png",
}

const _STATUS_NAMES: Array = ["Poison", "Blind", "Sleep", "Silence", "Paralysis", "Confusion", "Disease", "Petrify"]


## Full item record reconstructed from the item (+ icon + item_explain) tables,
## matching the shape items.json used to provide, or {} if unknown. Cached per id.
## The old multi-language `strings` block is reduced to the English entries the
## game actually reads (item.gd / shop_item_row read desc_short[0] / first entry).
func get_item(item_id) -> Dictionary:
	var key: String = str(item_id)
	if _item_cache.has(key):
		return _item_cache[key]
	var rows: Array = query(
		"SELECT i.*, COALESCE(ic.iconFile, '') AS iconFile,"
		+ " COALESCE(e.explainShort, '') AS explainShort, COALESCE(e.explainLong, '') AS explainLong"
		+ " FROM item i"
		+ " LEFT JOIN icon ic ON ic.iconId = i.iconId"
		+ " LEFT JOIN item_explain e ON e.itemId = i.itemId"
		+ " WHERE i.itemId = ? LIMIT 1",
		[key]
	)
	if rows.is_empty():
		return {}
	var built: Dictionary = _build_item_record(rows[0])
	_item_cache[key] = built
	return built


func _build_item_record(row: Dictionary) -> Dictionary:
	var use_case: PackedStringArray = _str_col(row, "useCase").split(",")
	var use_way: String = _str_col(row, "useWay")
	var flags: Array = []
	if use_way != "":
		for v in use_way.split(","):
			flags.append(str(v) == "1")
	var cat: String = _str_col(row, "category")
	var record: Dictionary = {
		"name": str(row.get("name", "")),
		"type": _ITEM_TYPE_NAMES.get(cat, cat),
		"compendium_id": int(row.get("QLfe23bu", 0)),
		"usable_in_combat": use_case.size() > 0 and str(use_case[0]) == "1",
		"usable_in_exploration": use_case.size() > 1 and str(use_case[1]) == "1",
		"flags": flags,
		"carry_limit": int(row.get("carryMaxNum", 0)),
		"stack_size": int(row.get("possessionLimit", 0)),
		"price_buy": int(row.get("priceBuy", 0)),
		"price_sell": int(row.get("priceSell", 0)),
		"icon": str(row.get("iconFile", "")),
		"strings": {
			"names": [str(row.get("name", ""))],
			"desc_short": [str(row.get("explainShort", ""))],
			"desc_long": [str(row.get("explainLong", ""))],
		},
	}
	# Old JSON shape: an effects array when the item has a process, else "".
	var effects_raw: Array = _decode_effects_raw(row)
	record["effects_raw"] = effects_raw if not effects_raw.is_empty() else ""
	return record


func get_all_prism() -> Array[String]:
	var rows = query("select itemId from item where name like \"%'s prism\"")
	var values: Array[String] = []
	values.assign(rows.map(func(dict): return str(dict["itemId"])))
	return values

# === Equipment ===

## Full equipment record reconstructed from equip_item (+ icon + explain) tables,
## matching equipment.json's shape for all consumed fields.
func get_equipment(equipment_id) -> Dictionary:
	var key: String = str(equipment_id)
	if _equipment_cache.has(key):
		return _equipment_cache[key]
	var rows: Array = query(
		"SELECT e.*, COALESCE(i.iconFile, '') AS iconFile,"
		+ " COALESCE(x.explainShort, '') AS explainShort, COALESCE(x.explainLong, '') AS explainLong"
		+ " FROM equip_item e"
		+ " LEFT JOIN icon i ON i.iconId = e.iconId"
		+ " LEFT JOIN equip_item_explain x ON x.equipId = e.equipId"
		+ " WHERE e.equipId = ? LIMIT 1",
		[key]
	)
	if rows.is_empty():
		return {}
	var built: Dictionary = _build_equipment_record(rows[0])
	_equipment_cache[key] = built
	return built


func _build_equipment_record(row: Dictionary) -> Dictionary:
	var slot_id: int = int(row.get("equipType", 0))
	var type_id: int = int(row.get("equipCategory", 0))
	var stats: Dictionary = {
		"HP": int(row.get("hp", 0)),
		"MP": int(row.get("mp", 0)),
		"ATK": int(row.get("atk", 0)),
		"DEF": int(row.get("def", 0)),
		"MAG": int(row.get("mag", 0)),
		"SPR": int(row.get("spr", 0)),
		"element_resist": _decode_named_value_map(_str_col(row, "elemResistValue"), _MAGIC_ELEMENTS),
		"status_resist": _decode_named_value_map(_str_col(row, "ailmentResistValue"), _STATUS_NAMES),
		"element_inflict": _decode_element_inflict(_str_col(row, "elementInflict")),
		"status_inflict": _decode_named_value_map(_str_col(row, "ailmentInflict"), _STATUS_NAMES),
	}
	return {
		"name": _str_col(row, "name"),
		"icon": _str_col(row, "iconFile"),
		"type_id": type_id,
		"slot_id": slot_id,
		"type": _EQUIP_TYPE_NAMES.get(str(type_id), str(type_id)),
		"slot": _EQUIP_SLOT_NAMES.get(str(slot_id), str(slot_id)),
		"type_icon": _EQUIP_TYPE_ICONS.get(str(type_id), ""),
		"is_twohanded": int(row.get("equipFeature", 0)) == 1,
		"compendium_id": int(row.get("QLfe23bu", 0)),
		"compendium_shown": int(row.get("dispDict", 0)) != 0,
		"rarity": int(row.get("52KBR9qV", 0)),
		"accuracy": int(row.get("ECbv61DK", 0)),
		"dmg_variance": null,
		"price_buy": int(row.get("priceBuy", 0)),
		"price_sell": int(row.get("priceSell", 0)),
		"skills": _decode_equipment_skill_ids(_str_col(row, "magicId"), _str_col(row, "abilityId")),
		"requirements": _decode_equipment_requirements(_str_col(row, "equipCondition")),
		"effects": [],
		"stats": stats,
		"strings": {
			"name": [_str_col(row, "name")],
			"desc_short": [_str_col(row, "explainShort")],
			"desc_long": [_str_col(row, "explainLong")],
		},
	}


## equipment.magicId and equipment.abilityId both carry passive ids in CSV form.
## Keep the original order, preserve 0 when present, and drop duplicates.
func _decode_equipment_skill_ids(skill_id_raw: String, bonus_raw: String) -> Array:
	var out: Array = []
	for raw in [skill_id_raw, bonus_raw]:
		if raw == "":
			continue
		for part in raw.split(","):
			var token: String = str(part).strip_edges()
			if token == "" or not token.is_valid_int():
				continue
			var value: int = int(token)
			if not out.has(value):
				out.append(value)
	return out


## equipCondition grammar used by equipment restrictions. Current IDs map as:
##   "3@<unitId[:unitId...]" -> ["UNIT_ID", unitId|[unitIds]]
## Unknown/empty conditions return null (same as JSON for unrestricted entries).
func _decode_equipment_requirements(raw: String) -> Variant:
	if raw == "":
		return null
	var parts: PackedStringArray = raw.split("@", true, 1)
	if parts.size() != 2:
		return null
	var kind: String = str(parts[0]).strip_edges()
	var payload: String = str(parts[1]).strip_edges()
	if kind != "3" or payload == "":
		return null
	var unit_ids: Array = []
	for token in payload.split(":"):
		var s: String = str(token).strip_edges()
		if s.is_valid_int():
			unit_ids.append(int(s))
	if unit_ids.is_empty():
		return null
	if unit_ids.size() == 1:
		return ["UNIT_ID", unit_ids[0]]
	return ["UNIT_ID", unit_ids]


## CSV value map decoder used by equipment stats (resists/inflicts). Returns null
## when every slot is zero/blank, otherwise {Name: value} for non-zero entries.
func _decode_named_value_map(raw: String, names: Array) -> Variant:
	if raw == "":
		return null
	var out: Dictionary = {}
	var vals: PackedStringArray = raw.split(",")
	for i in range(min(vals.size(), names.size())):
		var v_raw: String = str(vals[i]).strip_edges()
		if not v_raw.is_valid_int():
			continue
		var v: int = int(v_raw)
		if v != 0:
			out[str(names[i])] = v
	return out if not out.is_empty() else null


## effects_raw: one entry per effect, [targetRange, target, processId, [params]].
## The effect count is the number of '@' groups in processId (or in target when
## processId is empty); target / targetRange broadcast their last group when they
## carry fewer groups than that. processParam groups are ','-joined slots that may
## hold nested sub-arrays, floats, or literal tokens (see _decode_param_token).
func _decode_effects_raw(row: Dictionary) -> Array:
	var target_raw: String = _str_col(row, "target")
	var range_raw: String = _str_col(row, "targetRange")
	var proc_raw: String = _str_col(row, "processId")
	var param_raw: String = _str_col(row, "processParam")
	var n: int = _group_count(proc_raw) if proc_raw != "" else _group_count(target_raw)
	return _build_effects_raw(n, target_raw, range_raw, proc_raw, param_raw)


## Builds effects_raw for `n` effects from the parallel '@'-group fields. target /
## targetRange / processId broadcast their last group when they carry fewer groups
## than n; each processParam group supplies one effect's params.
func _build_effects_raw(n: int, target_raw: String, range_raw: String, proc_raw: String, param_raw: String) -> Array:
	if n == 0:
		return []
	var targets: PackedStringArray = target_raw.split("@")
	var ranges: PackedStringArray = range_raw.split("@")
	var procs: PackedStringArray = proc_raw.split("@")
	var params: PackedStringArray = param_raw.split("@")
	var out: Array = []
	for i in range(n):
		var param_list: Array = []
		if i < params.size():
			for p in str(params[i]).split(","):
				param_list.append(_decode_param_token(str(p)))
		out.append([
			_int_broadcast(ranges, i),
			_int_broadcast(targets, i),
			_int_broadcast(procs, i),
			param_list,
		])
	return out


## attackFrames grammar: '@' separates action groups, '-' separates hits within a
## group, each hit is 'frame:damage:x:y'. Fills attack_frames / attack_damage (one
## inner array per group) and attack_count (hit count per group).
func _decode_attack_frames(raw: String, out_frames: Array, out_damage: Array, out_count: Array) -> void:
	if raw == "":
		# No attack data still maps to one empty group ([[]] / [[]] / [0]), matching
		# the shape the old JSON carried for non-attacking spells.
		out_frames.append([])
		out_damage.append([])
		out_count.append(0)
		return
	for group in raw.split("@"):
		var frames: Array = []
		var damage: Array = []
		var hits: int = 0
		for hit in str(group).split("-"):
			var parts: PackedStringArray = str(hit).split(":")
			var fr: String = str(parts[0]).strip_edges() if parts.size() >= 1 else ""
			if fr.is_valid_int():
				frames.append(int(fr))
			var dm: String = str(parts[1]).strip_edges() if parts.size() >= 2 else ""
			if dm.is_valid_int():
				damage.append(int(dm))
			hits += 1
		out_frames.append(frames)
		out_damage.append(damage)
		out_count.append(hits)


## effectFrames grammar: '@' separates groups, '&' separates sub-effects, each is
## 'frame:resourceId:...'. effect_frames carries one inner array of frame numbers
## per group.
func _decode_effect_frames(raw: String) -> Array:
	if raw == "":
		return []
	var out: Array = []
	for group in raw.split("@"):
		var frames: Array = []
		for sub in str(group).split("&"):
			var parts: PackedStringArray = str(sub).split(":")
			if parts.size() >= 1 and str(parts[0]).is_valid_int():
				frames.append(int(parts[0]))
		out.append(frames)
	return out


## element_inflict: names of the inflicted elements (the non-zero slots of the
## 8-value `element` column), or null when the skill is non-elemental.
func _decode_element_inflict(raw: String) -> Variant:
	if raw == "":
		return null
	var names: Array = []
	var vals: PackedStringArray = raw.split(",")
	for i in range(min(vals.size(), _MAGIC_ELEMENTS.size())):
		var v: String = str(vals[i]).strip_edges()
		if v != "" and v != "0":
			names.append(_MAGIC_ELEMENTS[i])
	return names if not names.is_empty() else null


func _group_count(s: String) -> int:
	return 0 if s == "" else s.split("@").size()


## Value of a parallel '@'-group field at effect index `i`, broadcasting the last
## group when the field carries fewer groups than there are effects (target /
## targetRange may list a single group that applies to every effect).
func _int_broadcast(arr: PackedStringArray, i: int) -> int:
	if arr.is_empty():
		return 0
	var idx: int = i if i < arr.size() else arr.size() - 1
	return int(arr[idx]) if str(arr[idx]).is_valid_int() else 0


## Reads a column as a String, mapping SQL NULL (godot-sqlite returns it as a null
## Variant) and missing keys to "" — so the delimited-field decoders never see the
## literal "<null>" that str(null) would otherwise produce.
func _str_col(row: Dictionary, key: String) -> String:
	var v: Variant = row.get(key)
	return "" if v == null else str(v)


## A single processParam slot. Usually a scalar, but a slot may be a nested array
## joined by '&' (magic) or ':' (abilities); each element (and a bare slot) is an
## int, a float (when it carries a '.'), or the raw string (e.g. "none", or a
## space-suffixed value the source left as text) — matching the old JSON exactly.
func _decode_param_token(token: String) -> Variant:
	if token.contains("&"):
		var sub: Array = []
		for q in token.split("&"):
			sub.append(_conv_token(str(q)))
		return sub
	if token.contains(":"):
		var sub: Array = []
		for q in token.split(":"):
			sub.append(_conv_token(str(q)))
		return sub
	return _conv_token(token)


func _conv_token(t: String) -> Variant:
	if t.is_valid_int():
		return int(t)
	if t.contains(".") and t.is_valid_float():
		return float(t)
	return t
