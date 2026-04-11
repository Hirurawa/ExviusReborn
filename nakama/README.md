Nakama Server Architecture (Project Exvius)
This directory contains the Lua modules that power the server-authoritative backend for Project Exvius. All critical game logic, validation, and database interactions occur here.
📂 Directory Structure
The server codebase is strictly modularized:
main.lua: The entry point. It registers all RPCs and initializes the server.
core/: Contains fundamental utilities, secure payload parsing, and logging.
features/: Contains domain-specific logic (e.g., economy.lua, inventory.lua, units.lua).
data/: (Optional/Future) Static server-side validation configurations.
💾 The Hybrid Storage System
To manage the massive scale of a gacha RPG, we use a Hybrid Storage approach across Nakama's storage engine.
1. Monolithic Storage (Fungible/Stackables)
Items that are identical and stackable (e.g., Potions, Awakening Materials, Gil) are stored in a single JSON dictionary.
Collection: "inventory"
Key: "stackables"
Structure: {"mat_iron": 99, "potion_01": 5}
2. Granular Storage (Non-Fungible/Unique)
Entities that have unique state, levels, or attachments (e.g., Units, Weapons, Armor) are stored as individual database rows.
Collections: "unit", "equipment"
Key: <uuid-v4-instance-id>
Structure (Unit): {"template_id": "10001", "level": 5, "equipment": {"r_hand": "uuid-123"}}
Structure (Equipment): {"template_id": "301000200", "equipped_to": "uuid-456"}
🛡️ Security & RPC Guidelines
When writing or modifying RPCs (Remote Procedure Calls), the following rules are absolute:
1. Strict Payload Parsing
Never use raw nk.json_decode(payload). All incoming client data must be routed through Utilities.parse_payload(payload) to ensure safe failure if the client sends malformed JSON.
2. Structured JSON Errors
Never use Lua's native error("msg") for application logic, as it crashes the RPC execution and returns a raw HTTP 500 to Godot.
DO: return nk.json_encode({error = "Not enough Lapis"})
DON'T: error("Not enough Lapis")
3. Batch Writes Only
When a player action modifies multiple collections (e.g., spending Lapis to summon a Unit), use Nakama's batched nk.storage_write(writes) to ensure atomic transactions. Do not perform isolated writes that could result in desynced state if the script fails halfway through.
4. Debug RPC Limits
Any RPCs intended for debugging or cheating (e.g., add_currency, summon_units) must enforce hardcoded limits (e.g., max 10,000 currency per call) to prevent catastrophic integer overflows during testing.