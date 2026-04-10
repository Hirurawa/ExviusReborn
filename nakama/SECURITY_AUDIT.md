# Nakama Server Logic & Security Audit

This report outlines security vulnerabilities, database inefficiencies, error handling flaws, and areas for improvement found in the Lua backend scripts (`nakama/modules/main.lua`).

## 1. Security Vulnerabilities
- **Arbitrary Resource Granting (Debug RPCs):** The `add_currency`, `add_item`, `add_unit_xp`, and `add_rank_xp` RPCs blindly trust client payloads to grant resources, money, items, and experience without any validation or server-side restrictions. While these act as debug tools, they are currently fully exposed, allowing any client to grant themselves infinite resources.
- **Unrestricted Summoning:** `summon_units` accepts an `amount` from the payload without applying any cost (e.g., deducting lapis or tickets). A malicious client could pass a massive number (e.g., `amount = 1000000`), potentially causing a Denial of Service (DoS) by timing out the server or overflowing memory.
- **Unrestricted Unit Awakening:** `awaken_unit` checks if a unit is at max level, but it does not consume any awakening materials or currency, nor does it validate if the player actually possesses the required items for the awakening.
- **Unvalidated Mission Execution:** `perform_mission` only checks if the player has enough NRG. It does not verify if the player has actually unlocked the mission, completed prerequisites, or if the mission ID is legitimate for their current progression level. (Note: Combat validation is intentionally excluded from this audit per requirements, but mission access control is still missing).

## 2. Database Inefficiencies
- **Monolithic Storage Objects (The "God Object" Anti-pattern):** Player units and items are stored as single massive JSON arrays (`player_units` and `player_items`). Every time a single unit gains XP, is awakened, or equips an item, the server fetches the *entire* array, modifies one element, and rewrites the *entire* array. As players collect hundreds of units and items, this will cause severe performance degradation and will eventually hit Nakama's storage object size limits.
- **Redundant Storage Reads/Writes in Stats:**
  - In `perform_mission` and `add_rank_xp`, the code calls `get_player_stats(context, "")` (which performs a read, and potentially a write if NRG regenerated). Then, a few lines later, it manually performs *another* `nk.storage_read` for `player_stats`, and finally an `nk.storage_write`. That is 2 reads and up to 2 writes for a single action, which should be optimized into a single batched read and write.

## 3. Error Handling
- **Unsafe JSON Decoding:** Almost all RPCs (e.g., `buy_item`, `perform_mission`, `equip_item`, `summon_units`) call `local request = nk.json_decode(payload)` directly. If the client sends an empty string or malformed JSON, this will raise a raw Lua error and crash the RPC, returning a generic 500 Internal Server Error instead of a clean, structured JSON error response.
- **Silent Failures on Server Boot:** The `read_json_file` helper catches file read or decode errors but returns `nil`, and the global declarations fallback to empty tables (`local units_data = read_json_file(...) or {}`). If a crucial file like `units.json` is missing or corrupted, the server boots successfully but will cause catastrophic runtime errors during gameplay rather than failing fast and cleanly at startup.

## 4. Room for Improvement
- **Granular Storage Design:** Transition units and items to use Nakama's object keys effectively. For example, store each unit as a separate storage object where the `collection` is `"unit"` and the `key` is the `instance_id`. This allows O(1) reads and writes for specific units and scales infinitely without payload bloat.
- **Extract Rank Up Logic:** The `while stats.rank < MaxRank...` loop is duplicated identically in both `add_rank_xp` and `perform_mission`. This logic should be extracted into a shared `process_rank_up(stats)` helper function to keep the codebase DRY.
- **Helper Function for RPC Payloads:** Create a reusable wrapper or helper function for parsing RPC payloads safely to avoid repeating `pcall` everywhere:
  ```lua
  local function parse_payload(payload)
      if not payload or payload == "" then return {} end
      local success, decoded = pcall(nk.json_decode, payload)
      if not success then return nil end
      return decoded
  end
  ```
- **Equip Item UX/Edge Case:** In `equip_item`, if a user tries to equip an item but doesn't have enough spare copies, the server silently unequips it from the first unit it finds holding one. This could lead to a confusing UX where equipment seemingly vanishes from other units. It may be better to return an error (`{error = "Item currently equipped by another unit"}`) and let the client explicitly prompt the user to unequip it first.
