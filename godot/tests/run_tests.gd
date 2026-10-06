extends SceneTree

## Headless test runner. On the first frame (once the project's autoloads exist, so
## scripts that name them can compile; see PARSER-NOTES.md §9) it loads every
## res://tests/**/test_*.gd, runs each test_* method on a fresh instance, prints one
## line per test and exits with code 1 if anything failed. An engine or script error
## raised during a test fails that test; warnings do not.
##
##   Godot_v4.6.2-stable_win64_console.exe --headless --path godot --script res://tests/run_tests.gd
##   ... --script res://tests/run_tests.gd -- --filter=chain
##
## --filter matches against "file::method". Redirect stdout to a file: output read
## through a pipe only shows up once the process exits.
##
## This script must not name any class_name script or autoload: it compiles before the
## autoloads are registered. Test files are loaded with load() once they are.

const TEST_ROOT: String = "res://tests"


## Collects errors raised while a test runs.
class ErrorCounter:
	extends Logger
	var errors: PackedStringArray = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var message: String = rationale if rationale != "" else code
		_mutex.lock()
		errors.append("%s (%s:%d %s)" % [message, file.get_file(), line, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> PackedStringArray:
		_mutex.lock()
		var taken: PackedStringArray = errors
		errors = PackedStringArray()
		_mutex.unlock()
		return taken


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var filter: String = _option("filter")
	var counter := ErrorCounter.new()
	OS.add_logger(counter)

	var passed: int = 0
	var failed: PackedStringArray = []
	for path in _find_tests(TEST_ROOT):
		counter.take()
		var script: GDScript = load(path)
		var load_errors: PackedStringArray = counter.take()
		if script == null or not script.can_instantiate() or not load_errors.is_empty():
			failed.append(path)
			print("[FAIL] %s does not load" % path)
			for error in load_errors:
				print("       %s" % error)
			continue
		for method in _test_methods(script):
			var test_name: String = "%s::%s" % [path.trim_prefix(TEST_ROOT + "/"), method]
			if filter != "" and not test_name.contains(filter):
				continue
			var problems: PackedStringArray = _run_test(script, method, counter)
			if problems.is_empty():
				passed += 1
				print("[PASS] %s" % test_name)
			else:
				failed.append(test_name)
				print("[FAIL] %s" % test_name)
				for problem in problems:
					print("       %s" % problem)

	OS.remove_logger(counter)
	print("")
	print("%d passed, %d failed" % [passed, failed.size()])
	for failed_name in failed:
		print("  failed: %s" % failed_name)
	quit(0 if failed.is_empty() else 1)


func _run_test(script: GDScript, method: String, counter: ErrorCounter) -> PackedStringArray:
	var instance: Object = script.new()
	if instance.has_method("before_each"):
		instance.call("before_each")
	instance.call(method)
	if instance.has_method("after_each"):
		instance.call("after_each")
	var problems: PackedStringArray = PackedStringArray(instance.get("failures"))
	for error in counter.take():
		problems.append("error: %s" % error)
	if int(instance.get("assertion_count")) == 0 and problems.is_empty():
		problems.append("no assertions ran")
	return problems


static func _test_methods(script: GDScript) -> PackedStringArray:
	var names := PackedStringArray()
	for method in script.get_script_method_list():
		var method_name: String = str(method.get("name", ""))
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	return names


static func _find_tests(dir_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	for sub in dir.get_directories():
		found.append_array(_find_tests(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	found.sort()
	return found


## Value of --name=value after the "--" separator, or "".
static func _option(option_name: String) -> String:
	var prefix: String = "--%s=" % option_name
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""
