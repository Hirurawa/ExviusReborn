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

## 3. Saved Unit Instance (Player Owned)

When a player summons or acquires a unit, it is instantiated and saved to the `player_units` collection in the Nakama storage backend.

```json
{
    "instance_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890", // Unique UUID for the player's specific unit
    "unit_id": "100000102", // References the static Unit Template ID
    "level": 1,
    "xp": 0,
    "current_rarity": 2,
    "next_xp": 100, // Marginal experience required for the next level
    "equipment": { // Maps equipment slots to the item ID currently equipped
        "r_hand": "301000200", 
        "l_hand": null,
        "head": null,
        "body": null,
        "acc_1": null,
        "acc_2": null
    }
}
```

## 4. Saved Equipment Instance (Player Inventory)

Player inventory (including equipment, materials, and consumables) is saved globally as a stackable list of objects in the `player_items` collection.

```json
[
    {
        "item_id": "301000200", // References the static Equipment/Item ID
        "quantity": 5 // Total amount of this item the player owns
    },
    {
        "item_id": "200000500",
        "quantity": 12
    }
]
```

## 5. Saved Player Stats (Player Stats)

Player stats (including rank, xp, and nrg) is saved globally as an object in the `player_stats` collection.

```json
{
  "xp": 8309,
  "rank": 34,
  "current_nrg": 284,
  "last_nrg_update_time": 1775824657
}
```

## 6. Saved Player Parties (Parties)

Player's parties are saved globally as an object in the `user_data` collection.

```json
{
  "parties": [
    {
      "name": "Party 1",
      "units": [
        "b019e4b9-96a5-4f2a-a664-b746b885fd26",
        "03d04f22-4a0d-48ff-b93f-62a1f2210365",
        "10a17f72-ef1a-40e8-abad-902fd7126b85",
        "",
        ""
      ]
    },
  ]
}
```