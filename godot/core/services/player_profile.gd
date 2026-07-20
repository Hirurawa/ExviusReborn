extends Node
## PlayerProfile — owns the per-save player progression scalars: rank, xp,
## next-rank xp threshold, energy bar (current/max/regen rate/timer) and the
## currency wallet (gil + lapis). Drives the NRG regen tick via `_process`.
##
## State previously held by DataManager that now lives here:
##   - current_rank, current_xp, next_rank_xp
##   - current_nrg, max_nrg, nrg_regen_rate_seconds, seconds_until_next_nrg
##   - gil, lapis
##   - rank_exp_data (loaded from rank_exp.json)
##   - rank_updated / nrg_updated / currency_updated signals
##
## Stats persistence (stats.json) still lives on DataManager because it bundles
## these values with `current_username` and `last_entered_mission_id` (which
## belong to AccountService and MissionService respectively); once those land
## the snapshot orchestration will move here too.

signal rank_updated(rank: int, xp: int, next_rank_xp: int)
signal nrg_updated(current_nrg: int, max_nrg: int, time_until_next: float)
signal currency_updated(gil: int, lapis: int)
# Fires only when a regen tick actually grants a point (not on every frame).
# DataManager persists the stats snapshot in response so the new NRG survives
# a relaunch.
signal nrg_regenerated(current_nrg: int)

const SNAPSHOT_FILE: String = "stats.json"

var current_rank: int = 1
var current_xp: int = 0
var next_rank_xp: int = 100
var current_nrg: int = 0
var max_nrg: int = 0
var nrg_regen_rate_seconds: int = 300
var seconds_until_next_nrg: float = 0.0

var gil: int = 0
var lapis: int = 0

var monster_kill_progress: Dictionary = {}

# Loaded from rank_exp.json: {rank: {"xp_needed": int, "energy": int}}
var rank_exp_data: Dictionary = {}


func _process(delta: float) -> void:
	if max_nrg > 0 and current_nrg < max_nrg:
		seconds_until_next_nrg -= delta
		if seconds_until_next_nrg <= 0:
			current_nrg += 1
			seconds_until_next_nrg = nrg_regen_rate_seconds
			nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)
			nrg_regenerated.emit(current_nrg)
		else:
			# Still ticking, UI might want to know for the timer
			nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)


func ensure_rank_exp_loaded() -> void:
	if rank_exp_data.is_empty():
		rank_exp_data = load_rank_exp_data()

func load_rank_exp_data() -> Dictionary:
	# Load and parse rank_exp.json.
	# JSON structure: {"<rank>": {"Exp": int, "Energy": int, ...}, ...}
	# Exp at rank N is treated as XP needed to advance FROM rank N TO rank N+1.
	# Result: rank_data[rank] = {"xp_needed": int, "energy": int}

	var rank_data: Dictionary = {}
	
	# 1. Load the JSON file as a standard Resource
	var json_resource: JSON = load("res://assets/static_data/rank_exp.json")
	
	# 2. Access the parsed dictionary/array directly via '.data'
	if json_resource and json_resource.data is Dictionary:
		var rows: Dictionary = json_resource.data
		var sorted_ranks: Array[int] = []
		for rank_key in rows.keys():
			var rank_text: String = str(rank_key).strip_edges()
			if rank_text == "" or not rank_text.is_valid_int():
				push_warning("Skipping rank_exp.json row with invalid rank key: %s" % str(rank_key))
				continue
			sorted_ranks.append(int(rank_text))

		sorted_ranks.sort()

		for rank in sorted_ranks:
			var row_value: Variant = rows.get(str(rank), null)
			if not (row_value is Dictionary):
				push_warning("Skipping rank %d in rank_exp.json: row is not an object" % rank)
				continue

			var row: Dictionary = row_value
			if not row.has("Exp") or not row.has("Energy"):
				push_warning("Skipping rank %d in rank_exp.json: missing Exp or Energy" % rank)
				continue

			var exp_raw: Variant = row.get("Exp", 0)
			var energy_raw: Variant = row.get("Energy", 0)
			if exp_raw == null:
				# Max rank rows commonly have null Exp (no further progression).
				continue
			if energy_raw == null:
				energy_raw = 0
			var xp_needed: int = int(exp_raw)
			var energy: int = int(energy_raw)
			if xp_needed <= 0:
				push_warning("Skipping rank %d in rank_exp.json: Exp must be > 0" % rank)
				continue

			rank_data[rank] = {
				"xp_needed": xp_needed,
				"energy": energy
			}
	return rank_data

func set_last_entered_mission(_mission_id: String) -> void:
	# Note: MissionService handles its own variable last_entered_mission_id,
	# but PlayerProfile bundles it into its stats snapshot.
	save_snapshot("start_mission")

func add_xp(amount: int) -> void:
	current_xp += amount
	while current_xp >= next_rank_xp:
		current_xp -= next_rank_xp
		current_rank += 1
		var rank_up_nrg_bonus: int = 0
		if rank_exp_data.has(current_rank):
			next_rank_xp = rank_exp_data[current_rank]["xp_needed"]
			max_nrg = rank_exp_data[current_rank]["energy"]
			rank_up_nrg_bonus = max_nrg
		else:
			if rank_exp_data.size() > 0:
				var last_rank = rank_exp_data.keys().max()
				next_rank_xp = rank_exp_data[last_rank]["xp_needed"]
				max_nrg = rank_exp_data[last_rank]["energy"]
				rank_up_nrg_bonus = max_nrg

		if rank_up_nrg_bonus > 0:
			current_nrg += rank_up_nrg_bonus

	save_snapshot("add_xp")

func add_gil(amount: int) -> void:
	gil += amount
	currency_updated.emit(gil, lapis)
	save_snapshot("add_gil")

func deduct_gil(amount: int) -> void:
	gil = maxi(0, gil - amount)
	currency_updated.emit(gil, lapis)
	save_snapshot("deduct_gil")

func add_lapis(amount: int) -> void:
	lapis += amount
	currency_updated.emit(gil, lapis)
	save_snapshot("add_lapis")

func deduct_nrg(amount: int) -> void:
	current_nrg = maxi(0, current_nrg - amount)
	nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)
	save_snapshot("deduct_nrg")

func reset_to_starter() -> void:
	ensure_rank_exp_loaded()
	current_rank = 1
	current_xp = 0
	next_rank_xp = int(rank_exp_data.get(1, {}).get("xp_needed", 100))
	max_nrg = int(rank_exp_data.get(1, {}).get("energy", 0))
	current_nrg = max_nrg
	nrg_regen_rate_seconds = 300
	seconds_until_next_nrg = 0.0
	gil = 0
	lapis = 0
	monster_kill_progress.clear()


func emit_all() -> void:
	rank_updated.emit(current_rank, current_xp, next_rank_xp)
	nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)
	currency_updated.emit(gil, lapis)


func _ready() -> void:
	# Persist regenerated NRG point so it survives a relaunch.
	nrg_regenerated.connect(_on_nrg_regenerated)


func _on_nrg_regenerated(_current_nrg: int) -> void:
	save_snapshot("nrg_regen")


# === Stats snapshot ===

func snapshot_payload() -> Dictionary:
	return {
		"rank": current_rank,
		"xp": current_xp,
		"next_rank_xp": next_rank_xp,
		"current_nrg": current_nrg,
		"max_nrg": max_nrg,
		"nrg_regen_rate_seconds": nrg_regen_rate_seconds,
		"seconds_until_next_nrg": seconds_until_next_nrg,
		"last_entered_mission_id": MissionService.last_entered_mission_id,
		"gil": gil,
		"lapis": lapis,
		"username": AccountService.current_username,
		"monster_kill_progress": monster_kill_progress
	}


func normalize_stats_payload(raw_payload: Variant) -> Dictionary:
	if not (raw_payload is Dictionary):
		return {
			"rank": 1,
			"xp": 0,
			"next_rank_xp": 100,
			"current_nrg": 0,
			"max_nrg": 0,
			"nrg_regen_rate_seconds": 300,
			"seconds_until_next_nrg": 0.0,
			"last_entered_mission_id": "",
			"gil": 0,
			"lapis": 0,
			"username": "",
			"monster_kill_progress": {}
		}

	var payload: Dictionary = raw_payload
	var m_progress = payload.get("monster_kill_progress", {})
	if typeof(m_progress) != TYPE_DICTIONARY:
		m_progress = {}

	return {
		"rank": int(payload.get("rank", 1)),
		"xp": int(payload.get("xp", 0)),
		"next_rank_xp": int(payload.get("next_rank_xp", 100)),
		"current_nrg": int(payload.get("current_nrg", 0)),
		"max_nrg": int(payload.get("max_nrg", 0)),
		"nrg_regen_rate_seconds": int(payload.get("nrg_regen_rate_seconds", 300)),
		"seconds_until_next_nrg": float(payload.get("seconds_until_next_nrg", 0.0)),
		"last_entered_mission_id": str(payload.get("last_entered_mission_id", "")),
		"gil": int(payload.get("gil", 0)),
		"lapis": int(payload.get("lapis", 0)),
		"username": str(payload.get("username", "")),
		"monster_kill_progress": m_progress
	}

func record_monster_kill(monster_id: String) -> void:
	if not monster_kill_progress.has(monster_id):
		monster_kill_progress[monster_id] = 0
	monster_kill_progress[monster_id] += 1
	save_snapshot("monster_kill")

func clear_monster_kill_progress(monster_ids: Array) -> void:
	var changed = false
	for m_id in monster_ids:
		var s_id = str(m_id)
		if monster_kill_progress.has(s_id):
			monster_kill_progress.erase(s_id)
			changed = true
	if changed:
		save_snapshot("clear_monster_kill")


func load_stats_from_local() -> Dictionary:
	var envelope: Dictionary = Persistence.load_snapshot(SNAPSHOT_FILE)
	if envelope.is_empty():
		return {}

	var data: Variant = envelope.get("data", {})
	if not (data is Dictionary):
		return {}

	return normalize_stats_payload(data)


func save_snapshot(source_event: String) -> void:
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), source_event)
