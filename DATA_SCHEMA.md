# Data Schema

This document serves as the definitive map for data manipulation across the game. It outlines the structure of our static game data templates and how dynamic player data is saved in the backend.

## 1. Static Unit Template (`units.json`)

Provides the base data and progression metrics for units. This is a high-level overview of the primary gameplay-related fields.

```json
{
    "100000102": {
        "name": "Rain",
        "rarity_min": 2,
        "rarity_max": 6,
        "job": "Knight",
        "equip": [1, 2, 3, 9, 15, 30, 31, 40, 41, 50, 51, 52, 60], // Array of valid equipment type IDs
        "entries": {
            "100000102": { // ID matching the base unit, often represents a specific rarity
                "rarity": 2,
                "stats": {
                    "HP": [378, 1144, 900, 450], // Base stats scaling arrays [min, max, etc.]
                    "MP": [15, 45, 150, 75],
                    "ATK": [14, 41, 65, 32],
                    "DEF": [13, 40, 65, 32],
                    "MAG": [13, 39, 65, 32],
                    "SPR": [12, 37, 65, 32]
                },
                "limitburst_id": 100000102,
                "attack_count": 2,
                "ability_slots": 1,
                "element_resist": [0, 0, 0, 0, 0, 0, 0, 0], // Fire, Ice, Lightning, Water, Wind, Earth, Light, Dark
                "status_resist": [0, 0, 0, 0, 0, 0, 0, 0], // Poison, Blind, Sleep, Silence, Paralysis, Confusion, Disease, Petrification
                "awakening": { // Requirements to upgrade to the next rarity
                    "gil": 750,
                    "materials": [
                        [200000500, 5], // [Item ID, Quantity]
                        [200000800, 3]
                    ]
                }
            }
        }
    }
}
```

## 2. Static Equipment Template (`equipment.json`)

Provides the static properties of equippable items (weapons, armor, accessories).

```json
{
    "301000200": {
        "name": "Bronze Knife",
        "rarity": 1,
        "type_id": 1,
        "type": "Short Sword",
        "slot_id": 1,
        "slot": "Weapon", // Valid slots include Weapon, Shield, Head, Body, Accessory
        "is_twohanded": false,
        "stats": {
            "HP": 0,
            "MP": 0,
            "ATK": 10,
            "DEF": 0,
            "MAG": 0,
            "SPR": 0,
            "element_resist": null,
            "element_inflict": null,
            "status_resist": null,
            "status_inflict": null
        },
        "price_buy": 100,
        "price_sell": 10
    }
}
```


## Terminology
* `template_id`: A static string ID from the datamine JSONs (e.g., "10001" for Iron Sword, "101" for Rain).
* `instance_id`: A unique UUID v4 assigned to a player's specific owned entity (e.g., "abc-123").

## 3. Player Units (Granular Storage)
* **Collection:** `"unit"`
* **Key:** `<instance_id>`
* **Description:** Each unit is saved as its own individual row in the database.
```json
{
  "instance_id": "b019e4b9-...",
  "template_id": "401006905",
  "level": 13,
  "current_rarity": 6,
  "equipment": {
    "r_hand": "uuid-of-equipment-1", 
    "head": "",
    "body": ""
  }
}
```



## 4. Player Inventory (Hybrid Storage)
The get_player_items_rpc returns a combined Dictionary containing both stackable items and unique equipment.
### A. Stackables (Fungible)
* **Collection**: "inventory"
* **Key**: "stackables"
* **Description**: A single dictionary mapping the static template_id to an integer quantity.
### B. Equipment (Non-Fungible)
* **Collection**: "equipment"
* **Key**: <instance_id>
* **Description**: Each piece of equipment is its own unique instance. It contains an equipped_to field which is either null or the instance_id of the unit holding it.
Example Payload from get_player_items_rpc:
```json
{
  "stackables": {
    "item_potion_01": 5,
    "mat_iron": 99
  },
  "equipment": [
    { 
      "instance_id": "uuid-1", 
      "template_id": "301000200", 
      "equipped_to": null 
    },
    { 
      "instance_id": "uuid-2", 
      "template_id": "301000200", 
      "equipped_to": "unit-uuid-5" 
    }
  ]
}
```

## 5. Critical RPC Payloads
Equipping an Item (rpc_equip_item)
Godot must pass the unique instance IDs, not the template IDs.
```json

{
  "unit_instance_id": "unit-uuid-5",
  "slot": "r_hand",
  "item_instance_id": "uuid-2"
}
```

## 6. Saved Player Stats (Player Stats)

Player stats (including rank, xp, and nrg) is saved globally as an object in the `player_stats` collection.

```json
{
  "xp": 8309, // The xp needed to reach the next rank
  "rank": 34,
  "current_nrg": 284,
  "last_nrg_update_time": 1775824657
}
```

## 7. Saved Player Parties (Parties)

Player's parties are saved globally as an object in the `user_data` collection.

```json
{
  "parties": [
    {
      "name": "Party 1",
      "units": [
        "b019e4b9-96a5-4f2a-a664-b746b885fd26", // Unique UUID for the player's specific unit
        "03d04f22-4a0d-48ff-b93f-62a1f2210365",
        "10a17f72-ef1a-40e8-abad-902fd7126b85",
        "",
        ""
      ]
    },
  ]
}
```