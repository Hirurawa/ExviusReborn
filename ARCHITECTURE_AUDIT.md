# Project Architecture & Structure Audit

This document serves as an architectural review of the current Godot client and Nakama backend repository structure. It outlines structural issues, naming convention violations, scalability bottlenecks, and provides actionable recommendations to prepare for a major logic refactor.

## 1. Glaring Structural Issues

### UI and Backend Logic Mixing
The `godot/ui/` directory currently acts as a catch-all for anything related to the front-end, but it is violating separation of concerns by mixing business/game state logic with view elements.
- **Example**: `godot/ui/battle_manager.gd` manages raw combat state (HP, turns, initialization) but sits alongside UI view scenes like `combat_ui.tscn`. The `BattleManager` is not a UI component; it is core combat logic.
- **Flat UI Structure**: Having all screens (`login_ui.tscn`, `shop_ui.tscn`, `map_ui.tscn`) in a single root folder makes it difficult to locate components that belong to specific systems. Standalone `.tscn` popups, components, and primary screens are all dumped into the same bucket.

### Backend Monolith
- The Nakama backend logic is entirely consolidated into `nakama/modules/main.lua`. As server-authoritative rules grow for combat, economy, matching, and guilds, this file will become unmaintainable.

*(Note: The `godot/assets/` directory is managed via an external subtree and was omitted from structural changes).*

---

## 2. Naming Violations

There is a widespread pattern of **Godot Scene naming violations**.

Your required convention states that Godot scenes should use `PascalCase`. However, nearly all `.tscn` files currently use `snake_case`.
- **Pattern Violation Examples**: `combat_ui.tscn`, `shop_ui.tscn`, `unit_detail_ui.tscn`, `game_ui.tscn`.
- **Scripts**: The scripts attached to these scenes (`combat_ui.gd`, etc.) correctly use `snake_case`, but the corresponding `.tscn` files should be renamed (e.g., `CombatUI.tscn`).

---

## 3. Scalability Bottlenecks

Based on the current architecture, scaling to 500+ units, 1,000+ items, and expanding gameplay features will result in the following nightmares:

1. **The "God File" Backend**: If all 1,000 items' specific logic, gacha pull rates, and combat server-authoritative validations live in `nakama/modules/main.lua`, you will face massive merge conflicts, testing issues, and unreadable code.
2. **"Needle in a Haystack" Godot Structure**: When implementing the 50th unique menu overlay (e.g., equipment crafting, guild management, specific item shops), the `godot/ui/` folder will become completely unnavigable without nested domain segregation.
3. **Autoload Bloat**: Currently, global state relies heavily on `DataManager.gd`. As the game grows, holding *all* game data—parties, items, banners, map data—inside a single singleton will consume massive RAM footprint and create huge coupling.

---

## 4. Actionable Recommendations

Before writing any new feature code, implement the following directory refactoring plan:

### Step 1: Reorganize Godot into Domain-Driven Features
Move away from a generic `ui/` folder and adopt a feature-based modular approach. Group logic, UI views, and specific sub-components together by context.

**Proposed Godot Directory Structure:**
```text
godot/
├── core/                   # Engine-level singletons (formerly autoloads)
│   ├── DataManager.gd
│   ├── UIManager.gd
│   └── Network/            # Break out ServerConnection here
├── features/               # Domain-driven feature modules
│   ├── battle/
│   │   ├── logic/
│   │   │   └── battle_manager.gd
│   │   ├── ui/
│   │   │   ├── CombatUI.tscn (Renamed to PascalCase)
│   │   │   ├── CombatUnitPanel.tscn
│   │   │   └── UnitStatsPopup.tscn
│   ├── outgame/            # Menus, Shop, Units
│   │   ├── shop/
│   │   │   ├── ShopUI.tscn
│   │   │   └── ShopItemRow.tscn
│   │   ├── units/
│   │   │   ├── UnitsUI.tscn
│   │   │   └── UnitDetailUI.tscn
│   │   ├── equipment/
│   │   │   └── EquipSelectionPopup.tscn
│   ├── shared/             # UI Components used everywhere
│   │   ├── BottomNav.tscn
│   │   └── TopHeader.tscn
```

### Step 2: Fix Naming Conventions
- Run a batch rename script across the Godot project to capitalize all `.tscn` files to `PascalCase` (e.g., `friends_ui.tscn` -> `FriendsUI.tscn`).
- Update `UIManager` push/pop string references to match these new file paths and names.

### Step 3: Modularize Nakama Lua Backend
Split the `main.lua` monolith into distinct domain modules to separate initialization, API endpoints, and utility functions.

**Proposed Nakama Directory Structure:**
```text
nakama/
├── modules/
│   ├── init.lua              # Replaces main.lua; registers RPCs and Match handlers
│   ├── data/                 # JSON/CSV static data
│   ├── core/
│   │   ├── utilities.lua     # CSV/JSON parsing helpers, logging
│   │   └── player_data.lua   # Player XP, max NRG calculations
│   ├── features/
│   │   ├── economy.lua       # buy_item, currency validation
│   │   ├── inventory.lua     # equip_item, storage writes
│   │   └── combat.lua        # Dungeon completion, rewards
```
*Note: In `init.lua`, you will use Lua's `require("core.utilities")` etc. to load and register the functions.*
