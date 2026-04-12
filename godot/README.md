# Godot Client Architecture (Project Exvius)
This directory contains the Godot 4.x project for Project Exvius. The frontend acts exclusively as a "dumb client"—a visual representation of the server's state.
## 🧠 The "Dumb UI" Philosophy
To maintain sanity in a project with thousands of UI nodes and complex RPG math, we strictly enforce the "Dumb UI" rule. UI scripts (.gd files attached to Control nodes) must only do two things: draw pixels and listen for clicks.
1. No Domain Math in the UI
UI scripts are not allowed to calculate HP percentages, evaluate drop rates, or parse deep dictionaries. Math is reserved for Managers. Visual math (panning, zooming, camera clamping) is the only exception.
2. The Void Request Pattern (Signal Up, Call Down)
UI nodes must never directly await server responses. Communication with the global state uses a one-way flow:
Action: The UI calls a void method: DataManager.request_buy_item(item_id, qty)
Processing: DataManager handles the await, communicates with Nakama, and updates its internal data.
Reaction: DataManager emits a global signal: signal inventory_updated
Redraw: The UI listens to inventory_updated and redraws itself based on the new state.
## 🏛 Core Singletons (Autoloads)
The game's logic is distributed across strictly segregated Autoloads:
DataManager.gd: The Brain. It holds the player's game state (owned_units, inventory), manages all Nakama server RPC calls, and bridges the gap between server payloads and the UI.
BattleManager.gd: The Combat Engine. Handles turn-based state machines, tracks current HP/MP, and broadcasts combat events (e.g., unit_took_damage).
StatCalculator.gd: Pure Math. Calculates final unit stats based on base stats, growth curves, and equipment. Only called by Managers, never by the UI.
AssetPatcher.gd: The Network Downloader. Strictly handles HTTP requests to fetch versioned JSON datamine manifests from the remote server.
TextureBuilder.gd (or SpriteManager): The Renderer. Takes raw byte arrays and JSON coordinate data from the hard drive and slices them into Godot Texture2D objects for the UI to display.
# ⚡ Performance & Engine Rules
1. Strict Static Typing
All GDScript code must use Godot 4's static typing (var count: int = 0, func do_thing() -> void:).
Guardrail: When dealing with loosely typed JSON data from Nakama or Dictionaries, use safe casting (as Dictionary, str(id)) to prevent runtime crash errors. Godot parses JSON object keys as Strings, so always cast float/int IDs to String before dictionary lookups.
2. Dynamic Texture Caching
Never use load() or ResourceLoader.load() inside a loop (e.g., populating an inventory grid). Dynamic paths must route through a local Dictionary cache to prevent disk-read frame stutters. preload() is acceptable, but only for static, constant scene paths at the top of a script.