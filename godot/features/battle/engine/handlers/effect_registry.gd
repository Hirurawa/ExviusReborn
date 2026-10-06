class_name EffectRegistry
extends RefCounted

## Maps opcode schema types to the handlers that run them. An effect whose type has no
## handler does not fail silently: the engine reports it with an EFFECT_UNSUPPORTED
## event. unknown_types() checks the registered types against the schema, so a typo
## in a handler's type list shows up at startup instead of never matching.

var _handlers: Dictionary = {}


## The registry the engine uses by default. Skill links (cooldown and use-limited
## wrappers, uses per battle, random casts, opcode 99) are not effects the engine runs
## on hit; it resolves them when the action is declared (BattleEngine.LINK_TYPES).
static func create_default() -> EffectRegistry:
	var registry := EffectRegistry.new()
	registry.register(StatDamageHandler.new())
	registry.register(PercentDamageHandler.new())
	registry.register(FixedDamageHandler.new())
	registry.register(RestoreHandler.new())
	registry.register(ReviveHandler.new())
	registry.register(LimitGaugeHandler.new())
	registry.register(EsperGaugeHandler.new())
	registry.register(StatusHandler.new())
	registry.register(CoverHandler.new())
	registry.register(CleanseHandler.new())
	registry.register(GrantHandler.new())
	registry.register(DelayHandler.new())
	registry.register(JumpHandler.new())
	return registry


func register(handler: EffectHandler) -> void:
	for type in handler.handled_types():
		_handlers[type] = handler


func handler_for(type: String) -> EffectHandler:
	return _handlers.get(type, null)


func handles(type: String) -> bool:
	return _handlers.has(type)


func types() -> PackedStringArray:
	return PackedStringArray(_handlers.keys())


## Registered types that `schema` does not define. Should always be empty.
func unknown_types(schema: Dictionary) -> PackedStringArray:
	var known: Dictionary = schema_types(schema)
	var out := PackedStringArray()
	for type in _handlers.keys():
		if not known.has(type):
			out.append(type)
	return out


## Types `schema` defines that have no handler yet.
func unhandled_types(schema: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for type in schema_types(schema).keys():
		if not _handlers.has(type):
			out.append(type)
	out.sort()
	return out


## Every type a schema defines, variants included, as a set.
static func schema_types(schema: Dictionary) -> Dictionary:
	var types_found: Dictionary = {}
	for entry in schema.values():
		if not entry is Dictionary:
			continue
		types_found[str(entry.get("type", ""))] = true
		for variant in entry.get("variants", []):
			types_found[str(variant.get("type", ""))] = true
	types_found.erase("")
	return types_found
