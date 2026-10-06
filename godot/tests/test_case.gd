extends RefCounted

## Base class for tests run by run_tests.gd. Assertions record failures instead of
## stopping the test, so one run reports every broken expectation. The names follow
## GUT's, so moving to GUT later is mostly a change of `extends`.

var failures: PackedStringArray = []
var assertion_count: int = 0


func assert_true(value: bool, text: String = "") -> void:
	_check(value, "expected true", text)


func assert_false(value: bool, text: String = "") -> void:
	_check(not value, "expected false", text)


func assert_eq(got: Variant, expected: Variant, text: String = "") -> void:
	_check(_same(got, expected), "expected %s, got %s" % [_show(expected), _show(got)], text)


func assert_ne(got: Variant, not_expected: Variant, text: String = "") -> void:
	_check(not _same(got, not_expected), "did not expect %s" % _show(got), text)


func assert_almost_eq(got: float, expected: float, tolerance: float, text: String = "") -> void:
	_check(absf(got - expected) <= tolerance, "expected %s +/- %s, got %s" % [expected, tolerance, got], text)


func assert_null(value: Variant, text: String = "") -> void:
	_check(value == null, "expected null, got %s" % _show(value), text)


func assert_not_null(value: Variant, text: String = "") -> void:
	_check(value != null, "expected a value, got null", text)


func assert_has(container: Variant, value: Variant, text: String = "") -> void:
	var found: bool = false
	if container is Array or container is Dictionary or container is String:
		found = container.has(value)
	elif typeof(container) >= TYPE_PACKED_BYTE_ARRAY:
		found = Array(container).has(value)
	_check(found, "expected %s to contain %s" % [_show(container), _show(value)], text)


func fail_test(text: String) -> void:
	_check(false, "failed", text)


func _check(passed: bool, detail: String, text: String) -> void:
	assertion_count += 1
	if not passed:
		failures.append("%s: %s" % [text, detail] if text != "" else detail)


## Equality that does not error on mismatched types (1 == "1" would).
static func _same(a: Variant, b: Variant) -> bool:
	var numeric: Array = [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numeric and typeof(b) in numeric:
		return a == b
	if typeof(a) != typeof(b):
		var strings: Array = [TYPE_STRING, TYPE_STRING_NAME]
		if typeof(a) in strings and typeof(b) in strings:
			return str(a) == str(b)
		return false
	return a == b


static func _show(value: Variant) -> String:
	if value is String or value is StringName:
		return "\"%s\"" % value
	return str(value)
