class_name CutsceneScreen
extends Control

## The screen cutscenes play on (UIManager's "cutscene_ui"), opened over whatever screen
## asked for them. StoryFlow opens it, plays one scene after another with play() and
## closes it. The stage moves its own camera, so it runs in a SubViewport the size of
## the screen; taps reach it through the container. The back button and Escape do
## nothing here: closing the screen under StoryFlow would leave the scene unwatched.
##
## The Skip button (top right) runs the scene to its end out of sight, a few thousand
## frames per screen frame: its switches and next location are kept as if it had been
## watched, and StoryFlow marks it watched. It skips the scene playing, not the ones
## after it.

## Frames of the scene run per screen frame while skipping (a long scene is ~8000).
const SKIP_STEPS_PER_FRAME: int = 2000
## A skipped scene still running after this many frames is ended where it is.
const SKIP_MAX_STEPS: int = 200000

## A scene ended, or the screen left the tree before it did ("closed").
signal _ended(reason: String)

var player: EventPlayer

var _container: SubViewportContainer
var _skip_button: TextureButton
var _skipping: bool = false
var _skipped_steps: int = 0


func _ready() -> void:
	set_meta("block_back_request", true)
	_container = $Container
	_skip_button = $SkipButton
	player = $Container/Viewport/Event
	player.finished.connect(func(reason: String) -> void: _ended.emit(reason))
	tree_exiting.connect(func() -> void: _ended.emit("closed"))
	_skip_button.pressed.connect(skip)


func _process(_delta: float) -> void:
	if not _skipping:
		return
	if not player.fast_forward(SKIP_STEPS_PER_FRAME):
		_skipping = false
		return
	_skipped_steps += SKIP_STEPS_PER_FRAME
	if _skipped_steps >= SKIP_MAX_STEPS:
		push_warning("CutsceneScreen: bin %s still running after %d skipped frames; ended where it is" % [player.bin_id, _skipped_steps])
		_skipping = false
		player.stop("skipped")


## Plays `scene` ({ bin_id, layer, switches }, as StoryFlow builds it) to its end:
## { reason (EventPlayer.finished's; "error" when nothing could start, "closed" when the
## screen went away first), next_location (op 0x59's, {} for none), switches (the
## scene's switches as it ended) }.
func play(scene: Dictionary) -> Dictionary:
	_skipping = false
	_skipped_steps = 0
	_container.visible = true
	_skip_button.visible = true
	if not player.play(str(scene["bin_id"]), int(scene["layer"]), scene["switches"]):
		return {"reason": "error", "next_location": {}, "switches": scene["switches"]}
	var reason: String = await _ended
	return {"reason": reason, "next_location": player.next_location.duplicate(), "switches": player.switches.duplicate()}


## Skips the scene playing: the stage goes dark and the scene runs to its end.
func skip() -> void:
	if _skipping or not player.running:
		return
	_skipping = true
	_skip_button.visible = false
	_container.visible = false
