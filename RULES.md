# Project Architecture & AI Coding Rules

Before generating any code or plans, you must strictly adhere to the Godot 4 architecture of this project. Do not deviate from these rules under any circumstances.

## 1. STRICT COMPOSITION (DUMB UI)
* Every UI element (menus, popups) is its own standalone `.tscn` file.
* UI scripts must NOT contain backend, server, or game state logic.
* UI scripts only handle internal visual logic and emit signals when user interaction occurs. 

## 2. UIMANAGER AUTOLOAD (NAVIGATION)
* All UI navigation is handled by a singleton `UIManager`.
* The UIManager uses a Menu Stack. 
* It dynamically loads and `instantiate()`s scenes when pushing, and uses `queue_free()` when popping. It does NOT hold references to hidden, pre-instanced scenes.

## 3. DATAMANAGER AUTOLOAD (STATE & BACKEND)
* All global game state, currency, inventory, and server connections live in the `DataManager` singleton.
* UI scenes must not call the server directly. They emit a signal (e.g., `signal purchase_requested(item_id)`).
* `DataManager` handles the logic, updates the state, and emits a response signal (e.g., `signal state_updated`). The UI connects to this signal to update its visuals.

## 4. NO SPAGHETTI REFERENCES
* Never use fragile node paths like `get_node("../../SomeNode")`.
* Communicate strictly via Signals ("Signal up, call down" or via Autoloads).

## 5. STRICT TYPE HINTING
* Use Godot 4 static typing for everything. 
* Variables: `var current_hp: int = 0`
* Functions: `func equip_item(item_id: String) -> void:`

## 6. STRICT NAMING CONVENTIONS
* Scripts and Directories: `snake_case` (e.g., `unit_panel.gd`)
* Scenes and Nodes in the Scene Tree: `PascalCase` (e.g., `UnitPanel.tscn`)
* Signals: past_tense (e.g., `signal item_equipped`, NOT `signal equip_item`)

## 7. GODOT 4 INSTANTIATION & LOADING
* Always use `.instantiate()`, NEVER the outdated `.instance()`.
* Use `@onready var` for node references at the top of the script.
* Use `preload("res://path/to/scene.tscn")` at the top of scripts for UI panels that will be instantiated multiple times in a loop.
