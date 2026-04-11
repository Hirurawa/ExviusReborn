# Project Exvius: Reborn
⚠️ LEGAL DISCLAIMER
This is a strictly personal, non-commercial, open-source educational project. It is an architectural experiment to recreate the systems of the discontinued mobile game Final Fantasy Brave Exvius using modern open-source tools. It is not intended for public release, monetization, or distribution. All datamined static assets belong to their original copyright holders.
## 📖 Overview
Project Exvius is a reverse-engineering and architectural hobby project aimed at seeing how close a solo developer can get to rebuilding the massive, complex infrastructure of a modern gacha RPG.
### The Core Loop
The project successfully recreates the core foundational loops of the original game:
### Gacha & Roster Management: Summoning units, tracking granular unique instances, and managing party formations.
### The Economy & Hybrid Inventory: Managing thousands of stackable fungible items (materials, consumables) alongside unique non-fungible equipment instances.
Stat Calculation & Equipping: Dynamically calculating complex unit stats based on base values, growth curves, and two-handed weapon logic.
### Server-Authoritative Combat: Executing map dungeons and mission rewards where the server validates the truth.
## 🛠 Tech Stack
This project utilizes a completely decoupled Client-Server architecture.
* **Game Engine (Client)**: Godot 4.x (GDScript)
* **Backend Server**: Heroic Labs Nakama
* **Server Logic**: Lua (Server-Authoritative RPCs)
* **Data Layer**: Versioned static JSON files (Datamines)
## 🏗 High-Level Architecture
To survive the immense scope and data complexity of a legacy gacha game, this repository strictly adheres to specific architectural patterns:
1. The "Dumb UI" Pattern (Frontend)
The Godot client is strictly decoupled. UI scripts (.gd) are not allowed to perform math, parse deep dictionaries, or make direct server calls. The UI uses a Void Request -> Global Signal pattern:
The UI says: "Player clicked Equip." (DataManager.request_equip_item())
The Managers handle the network call and emit a signal: signal inventory_updated
The UI listens to the signal and simply redraws its pixels.
2. Hybrid Storage (Backend)
To optimize server costs and network payloads, the Nakama database stores player data in two distinct ways:
Monolithic Storage (Stackables): Potions and materials are stored as a single flat dictionary ({"potion_01": 55}).
Granular Storage (Equipment & Units): Swords and Heroes are stored as individual database rows with unique UUIDs (instance_id), allowing them to hold unique state data (e.g., "Equipped to Unit A").
3. Server Authority
The client never decides if a player has enough Lapis to summon, or if a mission was successfully completed. Godot submits intents to Nakama via RPCs, Nakama performs the secure Lua validation, and Godot updates its state based on the server's response.
## 🚀 Quick Start Guide
1. Spin up the Nakama Server
The backend runs locally via Docker. Ensure Docker Desktop is running.
Navigate to the nakama/ directory.
Run the command: docker-compose up -d
The Nakama console is now accessible at http://127.0.0.1:7351 (Default credentials: admin / password).
2. Launch the Godot Client
Open the godot/ folder in the Godot 4.x editor.
Ensure your DataManager singleton is pointed to the local Nakama instance (127.0.0.1:7350).
Hit Play!
For detailed guidelines on modifying the backend or the client, please refer to nakama/README.md and godot/README.md.