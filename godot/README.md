# Godot Client Architecture

This folder contains the Godot 4.6 client. The client follows a strict composition model:

- UI scenes are dumb and event-driven.
- Global state lives in domain-specific service autoloads.
- Navigation is centralized in `UIManager`.

## Core Principles

1. Dumb UI only
- UI scripts should only handle presentation and local interaction.
- UI should not perform backend calls directly.
- UI should not own global state.

2. Signal up, service down
- UI emits intent (or calls service request methods).
- Domain services (e.g. `UnitService`, `InventoryService`) perform async work and write local state.
- Services emit update signals.
- UI redraws from service state.

3. No fragile node path coupling
- Avoid deep relative node path usage for cross-feature communication.
- Prefer signal wiring and autoload interfaces.

4. Strict typing in GDScript
- Type variables, params, and returns whenever practical.
- Cast dictionary/JSON values deliberately (`int(...)`, `str(...)`, `as Dictionary`, etc).

## Autoloads and Responsibilities

Configured in [project.godot](project.godot):

- `Log`: Structured logging service.
- `AudioService`: Music and SFX playback.
- `StaticDataLoader`: Manages the baked JSON cache lifecycle (cold rebuild, warm load, signature validation).
- `Persistence`: Local file-based shadow save system (`user://` snapshots).
- `StaticData`: Lazy per-dataset accessor for JSON-sourced static data.
- `GameDatabase`: Read-only SQLite connection to `ffbe-data.db` (world map, missions, combat, towns, dungeons).
- `SkillResolver`: Resolves ability and passive skill data.
- `FriendsService`: Friend list state.
- `CombatItemsService`: Combat item slot management.
- `InventoryService`: Stackable items and equipment inventory.
- `PlayerProfile`: Player stats, rank, and profile data.
- `AccountService`: Account/session state.
- `MissionService`: Mission progress, start, and finish flow.
- `EsperService`: Esper ownership, board, and training.
- `PartyService`: Party composition and selection.
- `UnitService`: Unit roster, enhancement, and awakening.
- `EquipmentValidator`: Equipment legality checks (dual wield, category rules).
- `UIManager`: Menu stack, scene push/pop, persistent overlays.
- `StatCalculator`: Pure stat computations.
- `TouchScrollInstaller`: Installs touch-scroll behaviour on ScrollContainers.
- `ButtonSoundInstaller`: Attaches click sounds to buttons globally.

## Startup Flow

- Main scene is [Main.tscn](Main.tscn).
- [main.gd](main.gd) calls `UIManager.set_root("login_ui")` on `_ready()`.
- `UIManager` instantiates scenes from `_scenes_map`, pushes to stack, and frees popped scenes with `queue_free()`.

## UI Navigation Contract

`UIManager` is the only place that should own menu-stack navigation:

- `push(scene_key, params)`
- `pop()`
- `pop_to_root()`
- `set_root(scene_key, params)`

Persistent overlays (header/bottom nav/home buttons) are loaded once and visibility is updated based on current scene key.

## Performance Rules

1. Preload static resources
- Use `preload()` for stable script/scene/resource paths.
- Do not call `load()` repeatedly inside loops.

2. Cache dynamic textures
- Route dynamic texture loads through a dictionary cache.
- Reuse cached `Texture2D` instances for repeat paths.

3. Keep UI frame-safe
- Avoid heavy parsing, patching, or backend awaits in UI scripts.
- Keep expensive work in managers/services and emit results.

## Running the Project

From Godot Editor:

1. Open this folder using [project.godot](project.godot).
2. Run the project with F5.

From CLI (if Godot is on PATH):

```powershell
godot --path godot --editor
godot --path godot --play
```

## Naming Conventions

- Script and directory names: `snake_case`
- Scene and node names: `PascalCase`
- Signals: past tense (e.g. `purchase_successful`, `units_updated`)