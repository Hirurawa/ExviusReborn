# Repository Guidelines

## Project Structure & Module Organization

`godot/` is the Godot 4.6 client. Shared systems and autoload services live in `godot/core/`; feature-specific scenes and scripts live in `godot/features/`; checks live in `godot/tests/`. Large runtime assets belong under `godot/assets/` and are intentionally not tracked. `bin_parser/` contains Python tools that convert FFBE map and event binaries into JSON blueprints. `build_pipeline.py` exports distributable builds. See `DATA_SCHEMA.md`, `godot/README.md`, and `bin_parser/README.md` before changing data or parser contracts.

## Build, Test, and Development Commands

- `godot --path godot --editor` opens the project in Godot.
- `godot --path godot --play` runs the configured main scene.
- `godot --headless --path godot --script tests/test_quest_system.gd` runs the quest-system assertions; success prints `QUEST_SYSTEM_OK`.
- `python bin_parser/parse.py 1103` regenerates one map blueprint; use `--all` to validate every available map asset.
- `python bin_parser/test_town_parser.py` checks parsed warp targets against the local asset corpus.
- `python build_pipeline.py` exports Windows and Android artifacts after `GODOT_EXE` is configured in the script and export templates are installed.

## Coding Style & Naming Conventions

Use tabs for GDScript indentation and Godot 4 static types for variables, parameters, and return values. Name scripts and directories `snake_case`, scenes and scene-tree nodes `PascalCase`, and signals in the past tense (`units_updated`). Use `.instantiate()`, `@onready` node references, and `preload()` for repeatedly instantiated resources. Follow nearby Python style: four spaces, `snake_case`, and standard-library modules unless an existing dependency is necessary.

## Architecture & Testing Guidelines

Keep UI scenes presentation-only. Domain services own state and mutations; `UIManager` owns navigation. Communicate across features through signals and autoload APIs, not deep node paths. Add the smallest assertion-based regression check for changed non-trivial behavior. Test names follow `test_*.gd` or `test_*.py`; no coverage percentage is currently enforced. Parser tests require the untracked asset corpus.

## Commit & Pull Request Guidelines

Recent commits use short, imperative summaries such as `Validate town map object semantics`; keep each commit focused. Pull requests should explain behavior and architecture impact, list commands run, link the relevant issue, and include screenshots or a short capture for visual UI changes. Do not commit generated builds, imported caches, save data, or copyrighted asset dumps.
