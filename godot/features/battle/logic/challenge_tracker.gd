class_name ChallengeTracker
extends RefCounted

var is_completed: bool = false
var is_failed: bool = false
var counter: int = 0 # Useful for "Do X multiple times" challenges

var _active_connections: Array[Dictionary] = []

func _init(default_complete: bool = false):
	is_completed = default_complete

# Helper to connect signals and remember them so we can clean them up later
func bind_signal(sig: Signal, callable: Callable):
	sig.connect(callable)
	_active_connections.append({"signal": sig, "callable": callable})

# MUST be called at the end of battle to prevent memory leaks!
func cleanup():
	for conn in _active_connections:
		if conn["signal"].is_connected(conn["callable"]):
			conn["signal"].disconnect(conn["callable"])
	_active_connections.clear()

func evaluate() -> bool:
	return is_completed and not is_failed
