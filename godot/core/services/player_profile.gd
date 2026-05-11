extends Node
## PlayerProfile — owns the per-save player progression scalars: rank, xp,
## next-rank xp threshold, energy bar (current/max/regen rate/timer) and the
## currency wallet (gil + lapis). Drives the NRG regen tick via `_process`.
##
## State previously held by DataManager that now lives here:
##   - current_rank, current_xp, next_rank_xp
##   - current_nrg, max_nrg, nrg_regen_rate_seconds, seconds_until_next_nrg
##   - gil, lapis
##   - rank_exp_data (loaded from rank-exp.csv)
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

# Loaded from rank-exp.csv: {rank: {"xp_needed": int, "energy": int}}
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
		rank_exp_data = StaticDataLoader.load_rank_exp_data()


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
		"username": AccountService.current_username
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
			"username": ""
		}

	var payload: Dictionary = raw_payload
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
		"username": str(payload.get("username", ""))
	}


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
