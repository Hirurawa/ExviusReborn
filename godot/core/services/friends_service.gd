extends Node
## FriendsService — placeholder for friends/social features.
##
## The game is currently offline-only; all calls return failure via
## `friend_action_result`. This service exists so that when networked friends
## are reintroduced, the integration point is already separated from
## DataManager and the rest of the autoloads.

signal friends_updated(friends: Object)
signal friend_action_result(success: bool, message: String)


func list_friends() -> Variant:
	friend_action_result.emit(false, "Friends not available in offline mode")
	return null


func add_friend(_username: String) -> void:
	friend_action_result.emit(false, "Friends not available in offline mode")


func delete_friend(_username: String) -> void:
	friend_action_result.emit(false, "Friends not available in offline mode")
