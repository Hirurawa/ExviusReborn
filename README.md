# Project Exvius: Reborn

## Legal Disclaimer
This is a personal, non-commercial, educational reverse-engineering project.

The goal is to study architecture and systems design inspired by the discontinued mobile game Final Fantasy Brave Exvius. It is not intended for monetization or public distribution. Datamined static assets remain the property of their original copyright holders.

## Overview
Project Exvius explores how to rebuild core systems of a large-scale gacha RPG using a local-first, offline architecture.

Current implemented focus areas include:
- Gacha and roster management with unique instance tracking.
- Hybrid inventory model for stackable and unique items.
- Dynamic unit stat calculation and equipment logic.
- Local-authoritative flow for combat, rewards, and validation.

## Tech Stack
- Client: Godot 4.6 with GDScript.
- Data layer: SQLite database (`ffbe-data.db`) for static game data; versioned JSON for remaining datasets.
- Persistence: Local file-based save system (`user://` shadow snapshots via `Persistence` autoload).

## Architecture Principles
This repository follows strict composition and service-driven orchestration.

1. Dumb UI
- UI scenes and scripts are presentation-only.
- UI does not call services directly for mutations.
- UI emits user-intent signals and redraws from service-provided state.

2. Service-based architecture
- State is owned by domain-specific service autoloads (e.g. `UnitService`, `InventoryService`, `PartyService`).
- `UIManager` owns menu navigation with push and pop stack semantics.

3. Local authority
- Game rules are validated and applied client-side by service autoloads.
- Persistent state is written to local shadow snapshots after every confirmed mutation.

4. Signal-first communication
- Avoid fragile deep node traversal.
- Use signals and autoload interfaces for cross-feature communication.

## Repository Layout
- godot/: Godot client project.
  - godot/core/: Shared service autoloads and systems.
  - godot/features/: Gameplay and outgame feature modules.
  - godot/assets/: Static assets and data files.
- bin_parser/: Python tools for parsing binary datamine files.
- scripts/: Build and utility scripts.
- build_pipeline.py: Asset pipeline entry point.

## Quick Start
### Launch the Godot client
1. Open the `godot/` folder in Godot 4.6 using `project.godot`.
2. Run the main scene with F5.

No backend or Docker setup is required. The game runs fully offline using local file persistence.

## Additional Documentation
- Client architecture and conventions: godot/README.md
- AI coding/architecture rules for this repo: AGENTS.md