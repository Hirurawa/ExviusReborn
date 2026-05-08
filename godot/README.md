# Godot Client Architecture

This folder contains the Godot 4.6 client. The client follows a strict composition model:

- UI scenes are dumb and event-driven.
- Global state and backend calls live in managers.
- Navigation is centralized in `UIManager`.

## Core Principles

1. Dumb UI only
- UI scripts should only handle presentation and local interaction.
- UI should not perform backend calls directly.
- UI should not own global state.

2. Signal up, manager down
- UI emits intent (or calls manager request methods).
- `DataManager` performs async/backend work.
- `DataManager` emits update signals.
- UI redraws from manager state.

3. No fragile node path coupling
- Avoid deep relative node path usage for cross-feature communication.
- Prefer signal wiring and autoload interfaces.

4. Strict typing in GDScript
- Type variables, params, and returns whenever practical.
- Cast dictionary/JSON values deliberately (`int(...)`, `str(...)`, `as Dictionary`, etc).

## Autoloads and Responsibilities

Configured in [project.godot](project.godot):

- `Nakama`: plugin singleton.
- `StaticDataLoader`: Loads static game data from bundled/cached JSON files into memory.
- `DataManager`: player/account/inventory/party/combat-items state plus backend orchestration.
- `UIManager`: menu stack, scene push/pop, persistent overlays.
- `StatCalculator`: pure stat computations.

## Startup Flow

- Main scene is [demo.tscn](demo.tscn).
- [demo.gd](demo.gd) calls `UIManager.set_root("login_ui")` on `_ready()`.
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