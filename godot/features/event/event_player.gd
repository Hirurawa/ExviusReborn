class_name EventPlayer
extends Node

## Plays cutscenes from event bins (CUTSCENE-PLAN.md section 4). Give it a story event
## (play_story_event) or a bin, a layer and switches (play). It draws the layer, starts
## the page that runs on its own there and steps it once per physics frame, 60 per
## second, as the original does. A warp (op 0x05) moves to another layer and starts
## that layer's page. Taps, clicks and ui_accept go to the cinema window.
##
## For a quick look, open Event.tscn, set story_event_id (1001001 is the prologue's
## crystal scene) or bin_id, and run the scene.

signal finished(reason: String)

@export var story_event_id: String = ""
@export var bin_id: String = ""
@export var layer_id: int = -1
@export var auto_start: bool = true

var stage: EventStage
var bin: EventBin = null
var interpreter: EventInterpreter = null
## Scene switches: the story event's, plus whatever the scripts set (op 0x0a).
var switches: Dictionary = {}
var running: bool = false
## Where the game goes after the cutscene (op 0x59): {"type": 0 mission or 1 town,
## "id": id}, or {} when the scripts name nothing.
var next_location: Dictionary = {}

var _last_tap_frame: int = -1
## Counts play() calls, so a fast-forward stops with the scene it started on.
var _plays: int = 0


func _ready() -> void:
	stage = $Stage
	if auto_start and (story_event_id != "" or bin_id != ""):
		_start_exported.call_deferred()


## Plays story event `id` from its bin, layer and switches. False when it cannot.
func play_story_event(id: String) -> bool:
	var scene: Dictionary = GameDatabase.get_story_event_scene(id)
	if scene.is_empty():
		push_warning("EventPlayer: no bin for story event %s" % id)
		return false
	print("EventPlayer: story event %s (%s) -> bin %s, layer %d, switches %s" % [
		id, scene["name"], scene["bin_id"], scene["layer"], scene["switches"]])
	return play(scene["bin_id"], scene["layer"], scene["switches"])


## Plays the scene that starts on its own on `layer` of bin `id` (-1: the bin's start
## layer) under `scene_switches`. False when there is no such bin or scene.
func play(id: String, layer: int = -1, scene_switches: Dictionary = {}) -> bool:
	var bin_path: String = EventBin.find_path(id)
	if bin_path == "":
		push_warning("EventPlayer: no event bin %s" % id)
		return false
	bin = EventBin.load_file(bin_path)
	if bin.error != "":
		push_error("EventPlayer: %s" % bin.error)
		return false
	bin_id = id
	_plays += 1
	switches = scene_switches.duplicate()
	next_location = {}
	stage.setup(bin, id)
	return _enter_layer(layer if layer >= 0 else bin.start_layer)


## One frame of the cutscene. _physics_process calls it; tests call it directly.
func step_frame() -> void:
	if not running:
		return
	stage.tick()
	interpreter.step()
	if not interpreter.next_location.is_empty():
		next_location = interpreter.next_location
	if not interpreter.done:
		return
	if interpreter.end_reason == "warp":
		_enter_layer(int(interpreter.warp["layer"]))  # stops by itself when nothing starts there
		return
	_stop(interpreter.end_reason)


## Runs up to `steps` frames of the scene at once, tapping through every line, as a
## skip does: the switches it sets and where it leads are kept, nothing waits to be
## seen. Stops when the scene ends, even if a listener starts the next one at once.
## False once the scene has ended.
func fast_forward(steps: int) -> bool:
	var scene: int = _plays
	for _i in steps:
		if not running or _plays != scene:
			return false
		stage.tap()
		step_frame()
	return running and _plays == scene


## Ends the scene where it is; finished emits `reason`.
func stop(reason: String) -> void:
	_stop(reason)


func _physics_process(_delta: float) -> void:
	step_frame()


## One press reaches here twice: the project emulates touch from the mouse (and
## Godot emulates the mouse from touch on phones), so a click arrives as a mouse
## button and a screen touch in the same frame. Only the first counts; otherwise a
## click while a line appears would complete it and dismiss it at once.
func _unhandled_input(event: InputEvent) -> void:
	if not running:
		return
	var pressed: bool = false
	if event is InputEventMouseButton:
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = event.pressed
	else:
		pressed = event.is_action_pressed("ui_accept")
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	var this_frame: int = Engine.get_process_frames()
	if this_frame == _last_tap_frame:
		return
	_last_tap_frame = this_frame
	stage.tap()


func _start_exported() -> void:
	if story_event_id != "":
		play_story_event(story_event_id)
	else:
		play(bin_id, layer_id)


func _enter_layer(layer: int) -> bool:
	stage.load_layer(layer, switches)
	var pages: Array = bin.autorun_pages(layer, switches)
	if pages.is_empty():
		push_warning("EventPlayer: nothing starts on layer %d of bin %s under %s" % [layer, bin_id, switches])
		_stop("no scene")
		return false
	if pages.size() > 1:
		push_warning("EventPlayer: %d pages start on layer %d of bin %s; playing the first" % [pages.size(), layer, bin_id])
	interpreter = EventInterpreter.new(bin, pages[0], stage, switches)
	running = true
	return true


func _stop(reason: String) -> void:
	if not running:
		return
	running = false
	if interpreter != null and not interpreter.skipped_ops.is_empty():
		print("EventPlayer: bin %s skipped opcodes %s" % [bin_id, _describe_ops(interpreter.skipped_ops)])
	finished.emit(reason)


static func _describe_ops(ops: Dictionary) -> String:
	var parts: PackedStringArray = []
	for op in ops:
		parts.append("0x%02x x%d" % [op, ops[op]])
	return ", ".join(parts)
