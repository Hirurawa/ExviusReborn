# Project Exvius: Reborn

## Legal Disclaimer
This is a personal, non-commercial, educational reverse-engineering project.

The goal is to study architecture and systems design inspired by the discontinued mobile game Final Fantasy Brave Exvius. It is not intended for monetization or public distribution. Datamined static assets remain the property of their original copyright holders.

## Overview
Project Exvius explores how to rebuild core systems of a large-scale gacha RPG using a decoupled client-server architecture.

Current implemented focus areas include:
- Gacha and roster management with unique instance tracking.
- Hybrid inventory model for stackable and unique items.
- Dynamic unit stat calculation and equipment logic.
- Server-authoritative flow for combat, rewards, and validation.

## Tech Stack
- Client: Godot 4.6 with GDScript.
- Backend: Heroic Labs Nakama.
- Server logic: Lua RPC modules.
- Data layer: Versioned JSON datasets.

## Architecture Principles
This repository follows strict composition and manager-driven orchestration.

1. Dumb UI
- UI scenes and scripts are presentation-only.
- UI does not call backend services directly.
- UI emits user-intent signals and redraws from manager-provided state.

2. Centralized Managers
- DataManager owns global state, backend orchestration, and authoritative updates.
- UIManager owns menu navigation with push and pop stack semantics.

3. Server Authority
- The client submits intent.
- Nakama validates and applies game rules.
- The client updates from validated server responses.

4. Signal-first communication
- Avoid fragile deep node traversal.
- Use signals and autoload interfaces for cross-feature communication.

## Repository Layout
- godot/: Godot client project.
- nakama/: Local backend, Docker compose, and Lua modules.
- assets/: Datamined/static assets and metadata.
- core/: Shared managers and systems.
- features/: Gameplay and outgame feature modules.

## Quick Start
### 1) Start backend services
Prerequisite: Docker Desktop is running.

From the repository root:

```powershell
cd nakama
docker-compose up -d
```

Nakama endpoints:
- API: http://127.0.0.1:7350
- Console: http://127.0.0.1:7351
- Default console credentials: admin / password

### 2) Launch the Godot client
1. Open the godot project in Godot 4.6.
2. Confirm client connection settings target local Nakama (127.0.0.1:7350).
3. Run the main scene.

## Additional Documentation
- Client architecture and conventions: godot/README.md
- Backend setup and modules: nakama/README.md
- AI coding/architecture rules for this repo: AGENTS.md

## Assets
The assets foder is huge, and is not checked in under source control. It is a subtree of DaddyRaegen's ffbe_asset_dump repo with some modifications. The final assets folder can be found here: https://drive.google.com/file/d/1DCw_qFpe03-rCnMiKMWAS5EV56XYO-GA/view?usp=drive_link

## THANK YOU!
- aEnigmatic/ffbe
    - Datamine files
- DaddyRaegen/ffbe_asset_dump
    - Assets
- dsxragnarok/ffbetool
    - Creating sprite animations
- u/Cysidus
    - Wiki
- u/NightWaIker
    - FFBE Memorial Edition
