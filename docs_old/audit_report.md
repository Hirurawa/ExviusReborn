# Godot Frontend Coupling & Best Practices Audit Report

## Overall Findings

This audit evaluates the Godot frontend codebase against the established rules in `AGENTS.md` and industry-standard Godot 4 best practices.

### 1. `godot/ui/login_ui.gd`
- **Godot 4 Violations:** Missing strict type hinting on variables (`var email`, `var password`) and function parameters/return types (e.g., `func _on_login_button_pressed()`).

### 2. `godot/ui/register_ui.gd`
- **Godot 4 Violations:** Missing strict type hinting on variables (`var username`, `var email`, `var password`) and function return types (e.g., `func _on_register_button_pressed()`).

### 3. `godot/ui/top_header.gd`
- **Godot 4 Violations:** Missing strict type hinting for variables inside functions (e.g., `var minutes`, `var seconds`, `var xp`, `var gil`, `var lapis`).

### 4. `godot/ui/bottom_nav.gd`
- **Godot 4 Violations:** Missing return type hints for `_ready()`.

### 5. `godot/ui/map_ui.gd`
- **Godot 4 Violations:**
  - Missing return type hints on some functions like `_ready()`.
  - Using `load()` inside loops (e.g., `load(icon_path)` and `load("res://icon.svg")` in `_on_map_subregion_selected()`). `preload()` is generally preferred but dynamic paths need `load()`. For `res://icon.svg`, it should be preloaded outside the loop or script-level.
- **Dumb UI Violations:** Contains direct API calls (`await DataManager.server_connection.get_dungeon_missions_async(mission_ids)`). UI should only emit signals or call `DataManager` methods that encapsulate the connection, not access `server_connection` directly.
- **Optimization:** Dynamic instantiation of UI nodes inside `_on_map_subregion_selected` and `_on_dungeon_clicked` could be optimized. Also, popup is instantiated dynamically rather than preloaded as a packed scene in some cases.

### 6. `godot/ui/shop_ui.gd`
- **Godot 4 Violations:**
  - Missing type hints for `shop_items` and `shop_equipments` arrays (e.g., `var shop_items: Array[String] = ...`).
  - Missing return type hints on functions (`_ready()`, `_populate_shop`, `_on_buy_requested`).
- **Optimization:** Uses `preload()` correctly for `item_row_template`.
- **Dumb UI Violations:** Modifies label text directly on error response instead of reacting to a signal. Wait, the `buy_item` returns a dictionary, which is an anti-pattern as UI shouldn't handle `await` API responses directly if following strict signals up. `DataManager.buy_item` should emit `purchase_successful` or `purchase_failed`, but instead it's called synchronously using `await`. `AGENTS.md` states "UI scenes must not call the server directly. They emit a signal...". Calling `DataManager.buy_item` directly and waiting is a slight deviation, although it's mediated through `DataManager`.

### 7. `godot/ui/summon_ui.gd`
- **Godot 4 Violations:**
  - The variable `summoned_units` from `await DataManager.summon_units(3)` should be type hinted if possible.
- **Dumb UI Violations:** Calling `await DataManager.summon_units(3)` directly in the UI script instead of emitting a signal (e.g., `signal summon_requested`) and waiting for a state update signal from DataManager.
- **Optimization:** Dynamic construction of UI nodes inside loops without a preloaded scene template (creating `VBoxContainer`, `Label`, `HSeparator` manually).

### 8. `godot/ui/items_ui.gd`
- **Godot 4 Violations:**
  - Missing return type hints on `_ready()` and `_on_items_updated()`.
  - Using `ResourceLoader.load()` inside a loop for `icon_name` in `_refresh_items_list()`. Although dynamic, this can cause stutter. A caching mechanism or preloading would be better.
- **Optimization:** Dynamic construction of UI nodes inside loops.

### 9. `godot/ui/units_ui.gd`
- **Godot 4 Violations:**
  - Missing return type hints on functions (e.g., `_ready()`, `_refresh_party_view()`).
  - Missing type hints on local variables (`var party`, `var unit_id`, etc).
  - Using `load(img_path)` inside a loop in `_refresh_party_view()`.

### 10. `godot/ui/unit_detail_ui.gd`
- **Godot 4 Violations:**
  - Missing return type hints on several functions.
  - Using `load(tex_path)` inside a loop in `_populate_equipment_content()`.
- **Dumb UI Violations:**
  - UI script is accessing raw game data and performing math/logic on frame dimensions directly.
- **Optimization:** The script manually parses a JSON and builds textures out of byte buffers. This logic is extremely heavy and completely violates "Dumb UI". It should be handled by a Resource or an Autoload/DataManager utility, not the UI script itself.

### 11. `godot/ui/combat_ui.gd`
- **Godot 4 Violations:**
  - Missing type hinting on local variables.
  - Using `load()` inside loops (e.g., `load(tex_path)` and `load("res://icon.svg")` in `_on_battle_state_ready()`).
- **Optimization:** Preloads `UnitPanelScene` which is good, but dynamically creates AnimatedSprite2D and wrapper controls in a loop instead of instantiating a prepared scene.
- **Dumb UI Violations:**
  - Contains extensive combat logic and state tracking (`battle_manager.turn_count`, calculating `pct = int((float(new_hp) / float(max_hp)) * 100.0)`). While `battle_manager` exists, `combat_ui` is calculating percentages.
  - Calling `DataManager.perform_mission(current_mission_id)` and manually resolving rewards math/string building directly in the UI (`if mission_data.has("gil"): rewards_text += ...`). This is heavy business logic that belongs in `DataManager` or `BattleManager`.

### 12. `godot/ui/friends_ui.gd`
- **Godot 4 Violations:** Missing return type hints on functions. Missing type hint on `var friend = friend_obj`.
- **Optimization:** Dynamically creates complex UI element blocks in loops using `HBoxContainer`, `Label`, `Button`. Should use a preloaded scene (`friend_row.tscn`).

### 13. `godot/ui/edit_profile_ui.gd`
- **Godot 4 Violations:** Missing return type hints on functions. Missing type hinting on variables.
- **Dumb UI Violations:** Direct `await DataManager.update_account(new_username)` instead of emitting signal.

### 14. `godot/ui/equip_selection_popup.gd`
- **Godot 4 Violations:** Missing return type hints on functions. Missing type hinting on variables.
- **Dumb UI Violations:**
  - Heavy logic calculating valid slots inside the UI script (`if "hand" in current_slot_id and (item_slot == "Weapon" or item_slot == "Shield")`). This logic should reside in the DataManager or a dedicated utility class, as it's game domain logic.
  - Calls `await DataManager.equip_item(...)` instead of emitting a signal.

### 15. `godot/ui/unit_selector_ui.gd`
- **Godot 4 Violations:** Missing return type hints on functions. Using `load(img_path)` inside a loop.
- **Dumb UI Violations:** Modifying party data directly (`parties[target_party_index]["units"][target_slot_index] = unit_inst.instance_id`) and then emitting a save request. The UI should only tell the DataManager *what* to do (e.g., `DataManager.assign_unit_to_party(party_index, slot_index, instance_id)`), not manipulate the deep dictionary directly.
- **Optimization:** Creating UI nodes dynamically in a loop instead of instantiating a preloaded scene.

### 16. `godot/ui/combat_unit_panel.gd`
- **Godot 4 Violations:** Missing strict type hints on local variables.

### 17. `godot/ui/unit_stats_popup.gd`
- **Godot 4 Violations:** Missing return type hints. Missing variable type hints.

### 18. `godot/ui/shop_item_row.gd`
- **Godot 4 Violations:** Missing return type hints. Missing variable type hints.
- **Optimization:** Uses `ResourceLoader.load()` inside the `setup` function, which might cause stuttering when a shop populates. Should use asynchronous loading or preloading.

### 19. `godot/autoloads/data_manager.gd`
- **Godot 4 Violations:**
  - Variables are missing strict static typing (`var server_connection`, `var owned_items = []`, etc.).
  - Methods missing return type hinting.

### 20. `godot/autoloads/ui_manager.gd`
- **Godot 4 Violations:**
  - `load()` is used instead of `preload()` for persistent overlays inside `_load_persistent_overlays()`, though acceptable if they might not exist, `ResourceLoader.exists()` check mitigates the risk.
- **Spaghetti References:** `canvas_layer.move_child` manipulation is used. While acceptable for a manager, it implies a tight coupling with the scene tree structure.

### 21. `godot/asset_patcher.gd`
- **Godot 4 Violations:** Missing type hints for most variables and functions.
- **Optimization:** The `user://data` directory check does `var dir = DirAccess.open("user://")` and `print(dir)`. Leftover debug code.

## General Summary

1. **Strict Type Hinting (Godot 4 Violations):** Almost all `.gd` files lack strict variable static typing (e.g., `var x` instead of `var x: int`) and missing return type hints (`-> void`) on core functions like `_ready()`.
2. **Spaghetti References:** The codebase is remarkably clean of relative `get_node("../../")` spaghetti. Signals and `@onready` are heavily utilized, which is excellent.
3. **Dumb UI Violations:**
   - Many UI scripts bypass the "Signal up" approach and call `DataManager` methods synchronously (using `await`). `AGENTS.md` specifically says "UI scenes must not call the server directly. They emit a signal... DataManager handles the logic...".
   - The UI often performs domain/business logic. E.g., `combat_ui.gd` processes mission rewards and parses strings. `unit_detail_ui.gd` manually parses JSON and byte arrays. `equip_selection_popup.gd` contains string parsing for valid equip slots.
   - `unit_selector_ui.gd` manually edits deep nested structures of `DataManager.parties` instead of calling a dedicated function on `DataManager`.
4. **Optimization:**
   - Excessive use of `load()` or `ResourceLoader.load()` inside `for` loops in lists/grids (`units_ui.gd`, `items_ui.gd`, `map_ui.gd`, etc).
   - In lists (like friends, units, items), the UI dynamically creates node trees (`HBoxContainer` -> `Label` -> `Button`) using `.new()` inside loops instead of creating a standalone `.tscn` (like `shop_item_row.tscn`) and using `preload().instantiate()`.
   - Hidden overlays: The `UIManager` preloads and hides things like `top_header`, `bottom_nav`, which is actually mentioned as standard in `AGENTS.md` memory context, but `MissionDetailsPopup` and `RewardsPopup` are sitting hidden in scene trees rather than instantiated dynamically.

*(End of Report)*

EXECUTION GUARDRAIL FOR AI: Refactor the UI in distinct passes, strictly adhering to AGENTS.md.

Pass 1 (Typing & Loops): Go through all files and add strict Godot 4 static typing. Replace load() inside loops with preload() at the top of the script.

Pass 2 (Dumb UI): Strip out business logic (math, JSON parsing) from scripts like combat_ui.gd and unit_detail_ui.gd. Route them through DataManager via signals. Do not attempt Pass 2 until Pass 1 is fully complete and functional.