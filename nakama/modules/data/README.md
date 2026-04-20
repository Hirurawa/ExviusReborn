FFBE
====

Data dump for Final Fantasy Brave Exvius (Global version)

* **units.json**

``` json
"215000105": { // Unit's static ID
    "rarity_min": 5, // Minimum rarity the unit gets summoned with
    "rarity_max": 7, // Maximum rarity achievable
    "name": "Noctis",
    "names": ["Noctis", "諾克提斯", "녹티스", "Noctis", "Noctis", "Noctis", "Noctis", "Noctis\u001a"],
    "game_id": 10015,
    "game": "FFXV",
    "job_id": 102,
    "job": "Prince",
    "sex_id": 1,
    "sex": "Male",
    "tribe_id": 5,
    "is_summonable": true,
    "TMR": ["EQUIP", 409011900], // Trust Master Reward: 0: Type of the reward, 1: ID
    "sTMR": ["MATERIA", 504227272], // Super Trust Master Reward
    "equip": [1, 2, 3, 4, 10, 13, 14, 30, 31, 40, 50, 51, 60], // The equipments usable by the unit
    "entries": { // Unit's stats by rarity
        "215000105": { // Unit's "rarity-specific" static ID
            "compendium_id": 616,
            "rarity": 5, // "current" rarity
            "roles": ["Versatile"],
            "categories": ["Fire", "Attacker", "Support", "Breaker", "FFXV", "Royal Arms", "The Saviors"],
            "leader_skill_id": null,
            "exp_pattern": 30, // Determines the xp neded for leveling up the unit -> referenced by the unit-exp-pattern.csv file
            "stat_pattern": 1,
            "stats": { // Base stats of the unit: 0: Minimum (at level 1), 1: Maximum (at max level), 2: Pots, 3: Door pots
                "HP": [964, 2920, 900, 450],
                "MP": [43, 130, 150, 75],
                "ATK": [40, 120, 65, 32],
                "DEF": [34, 104, 65, 32],
                "MAG": [38, 115, 65, 32],
                "SPR": [33, 101, 65, 32]
            },
            "limitburst_id": 215000105, // Static ID referenced by limitbursts.json
            "attack_count": 3, // Number of attacks the unit's basic attack do
            "attack_damage": [ // The damage per hit the unit's basic attack do
                [60, 20, 20]
            ],
            "attack_frames": [52, 74, 87], // The frame the basic attack lands
            "effect_frames": [50, 50, 72, 85],
            "max_lb_drop": 4,
            "ability_slots": 4, // Number of ability the unit can equip
            "magic_affinity": [7, 7, 0, 0], // 0: White, 1: Black, 2: Grren, 3: Blue
            "element_resist": [0, 0, 0, 0, 0, 0, 0, 0], // "FIRE", "ICE", "LIGHTNING", "WATER", "WIND", "EARTH", "LIGHT", "DARK"
            "status_resist": [0, 0, 0, 0, 0, 0, 0, 0], // "POISON", "BLIND", "SLEEP", "SILENCE", "PARALYSIS", "CONFUSION", "DISEASE", "PETRIFY"
            "physical_resist": 0,
            "magical_resist": 0,
            "awakening": { // Resources needed to reach the next rarity
                "gil": 4000,
                "materials": { // Key: Material ID referenced by the items.json, Value: Number of the specified material
                    "290060200": 20,
                    "290060400": 10,
                    "290060300": 10,
                    "290060100": 5,
                    "290050500": 5
                }
            },
            "nv_upgrade": null,
            "brave_shift": null
        },
        "215000106": {
            "compendium_id": 617,
            "rarity": 6,
            "roles": ["Versatile"],
            "categories": ["Fire", "Attacker", "Support", "Breaker", "FFXV", "Royal Arms", "The Saviors"],
            "leader_skill_id": null,
            "exp_pattern": 30,
            "stat_pattern": 1,
            "stats": {
                "HP": [1262, 3824, 900, 450],
                "MP": [57, 174, 150, 75],
                "ATK": [52, 158, 65, 32],
                "DEF": [40, 120, 65, 32],
                "MAG": [50, 150, 65, 32],
                "SPR": [45, 136, 65, 32]
            },
            "limitburst_id": 215000106,
            "attack_count": 3,
            "attack_damage": [
                [60, 20, 20]
            ],
            "attack_frames": [52, 74, 87],
            "effect_frames": [50, 50, 72, 85],
            "max_lb_drop": 4,
            "ability_slots": 4,
            "magic_affinity": [8, 8, 0, 0],
            "element_resist": [0, 0, 0, 0, 0, 0, 0, 0],
            "status_resist": [0, 0, 0, 0, 0, 0, 0, 0],
            "physical_resist": 0,
            "magical_resist": 0,
            "awakening": {
                "gil": 3000000,
                "materials": {
                    "300000370": 1
                }
            },
            "nv_upgrade": null,
            "brave_shift": null
        },
        "215000107": {
            "compendium_id": 1035,
            "rarity": 7,
            "roles": ["Versatile"],
            "categories": ["Fire", "Attacker", "Support", "Breaker", "FFXV", "Royal Arms", "The Saviors"],
            "leader_skill_id": 10000195,
            "exp_pattern": 30,
            "stat_pattern": 4,
            "stats": {
                "HP": [1640, 4971, 900, 450],
                "MP": [75, 226, 150, 75],
                "ATK": [67, 202, 65, 32],
                "DEF": [64, 194, 65, 32],
                "MAG": [64, 195, 65, 32],
                "SPR": [63, 192, 65, 32]
            },
            "limitburst_id": 215000107,
            "attack_count": 3,
            "attack_damage": [
                [60, 20, 20]
            ],
            "attack_frames": [52, 74, 87],
            "effect_frames": [50, 50, 72, 85],
            "max_lb_drop": 4,
            "ability_slots": 4,
            "magic_affinity": [8, 8, 0, 0],
            "element_resist": [0, 0, 0, 0, 0, 0, 0, 0],
            "status_resist": [0, 0, 0, 0, 0, 0, 0, 0],
            "physical_resist": 0,
            "magical_resist": 0,
            "awakening": null,
            "nv_upgrade": null,
            "brave_shift": null
        }
    },
    "skills": [ // List of skill the unit unlocks at the specified rarity's specified level. Type: Could be "ABILITY" or "MAGIC". Id: The static id of the ablility referenced by the skills_magic.json if the type is "MAGIC" or the skills_ability.json or the skills_passive.json if the type is "ABILITY"
        {"rarity": 5, "level": 1, "type": "ABILITY", "id": 211750},
        {"rarity": 5, "level": 1, "type": "ABILITY", "id": 211890},
        {"rarity": 5, "level": 12, "type": "ABILITY", "id": 211860},
        {"rarity": 5, "level": 20, "type": "ABILITY", "id": 211900},
        {"rarity": 5, "level": 30, "type": "ABILITY", "id": 211820},
        {"rarity": 5, "level": 42, "type": "ABILITY", "id": 211910},
        {"rarity": 5, "level": 55, "type": "ABILITY", "id": 211800},
        {"rarity": 5, "level": 58, "type": "ABILITY", "id": 211960},
        {"rarity": 5, "level": 74, "type": "ABILITY", "id": 211950},
        {"rarity": 5, "level": 80, "type": "ABILITY", "id": 211780},
        {"rarity": 5, "level": 80, "type": "ABILITY", "id": 100740},
        {"rarity": 6, "level": 1, "type": "ABILITY", "id": 211870},
        {"rarity": 6, "level": 4, "type": "ABILITY", "id": 211940},
        {"rarity": 6, "level": 15, "type": "ABILITY", "id": 211920},
        {"rarity": 6, "level": 30, "type": "ABILITY", "id": 211830},
        {"rarity": 6, "level": 30, "type": "ABILITY", "id": 211840},
        {"rarity": 6, "level": 30, "type": "ABILITY", "id": 211850},
        {"rarity": 6, "level": 40, "type": "ABILITY", "id": 211880},
        {"rarity": 6, "level": 52, "type": "ABILITY", "id": 211770},
        {"rarity": 6, "level": 60, "type": "ABILITY", "id": 211930},
        {"rarity": 6, "level": 70, "type": "ABILITY", "id": 211810},
        {"rarity": 6, "level": 92, "type": "ABILITY", "id": 211970},
        {"rarity": 6, "level": 100, "type": "ABILITY", "id": 211760},
        {"rarity": 7, "level": 101, "type": "ABILITY", "id": 227180},
        {"rarity": 7, "level": 101, "type": "ABILITY", "id": 100220},
        {"rarity": 7, "level": 105, "type": "ABILITY", "id": 227181},
        {"rarity": 7, "level": 110, "type": "ABILITY", "id": 227182},
        {"rarity": 7, "level": 110, "type": "ABILITY", "id": 227183},
        {"rarity": 7, "level": 115, "type": "ABILITY", "id": 100111},
        {"rarity": 7, "level": 120, "type": "ABILITY", "id": 227184}
    ]
}
```

* **skills_.json**
** Ability
```json
"912190": { // Ability's static ID
    "name": "Bolting Strike",
    "icon": "global_ability_10061.png",
    "compendium_id": 85910,
    "rarity": 9,
    "cost": {"MP": 42},
    "attack_count": [9], // Number of hits the ability does
    "attack_damage": [[7,  7,  7,  7,  7,  7,  7,  7,  44]], // The percent of damage each of the hits do
    "attack_frames": [[42,  48,  54,  60,  66,  72,  78,  84,  90]], // The frames the hits land
    "effect_frames": [[38,  38,  90,  65,  38,  0,  2]],
    "move_type": 4,
    "motion_type": 2,
    "effect_type": "Default",
    "attack_type": "Physical",
    "element_inflict": null, // The array of element(s) the ability uses. For example: ["Lightning"]
    "effects": [ // The text description of the ability's effects
        ["Physical damage (25x * 2 = 50x, ATK) to all enemies (ignore cover)"],
        ["Reduce DEF by 70% for 5 turns to all enemies"],
        ["Increase LB gauge by 20 to caster"]
    ],
    "effects_raw": [[2, 1, 21, [0,  0,  2500,  -50]], [2, 1, 24, [0,  -70,  0,  0,  5,  1]], [0, 3, 125, [2000,  2000]]], // The raw effects of the ability
    "requirements": null
}
```
** Magic
```json
"20390": {
    "name": "Tornado",
    "icon": "ability_31.png",
    "compendium_id": 138,
    "rarity": 8,
    "cost": {"MP": 48},
    "magic_type": "Black",
    "is_sealable": false,
    "is_reflectable": false,
    "in_exploration": false,
    "attack_count": [9, 1],
    "attack_damage": [[11,  11,  11,  11,  11,  11,  11,  11,  12], [100]],
    "attack_frames": [[80,  92,  104,  116,  128,  140,  152,  164,  176], [80]],
    "effect_frames": [[40,  40], [40,  40]],
    "move_type": 0,
    "effect_type": "Default",
    "attack_type": "Magic",
    "element_inflict": ["Wind"],
    "effects": [
        ["Magic wind damage (24x, MAG) to all enemies"],
        ["Reduce resistance to Wind by 100% for 5 turns to all enemies"]
    ],
    "effects_raw": [[2, 1, 15, [0,  0,  0,  0,  0,  2400,  0]], [2, 1, 33, [0,  0,  0,  0,  -100,  0,  0,  0,  1,  5]]],
    "requirements": null
}
```
** Passive
```json
"100010": {
    "name": "HP +10%",
    "icon": "ability_77.png",
    "compendium_id": 1,
    "rarity": 1,
    "unique": false,
    "effect_type": "Default",
    "attack_type": "None",
    "element_inflict": null,
    "effects": [
        ["Increase HP by 10%"]
    ],
    "effects_raw": [[1, 3, 1, [0,  0,  0,  0,  10,  0,  0]]],
    "requirements": null
},
```

* **limitbursts.json**
```json
"100000102": {
    "name": "Flame Sword",
    "cost": 0,
    "attack_count": [2],
    "attack_damage": [[20,  80]],
    "attack_frames": [[3,  59]],
    "effect_frames": [[0]],
    "move_type": 1,
    "damage_type": "Physical",
    "element_inflict": ["Fire"],
    "min_level": [
        ["Physical fire damage (1.8x, ATK) to one enemy"]
    ],
    "max_level": [
        ["Physical fire damage (2x, ATK) to one enemy"]
    ],
    "levels": [[8, [[1, 1, 1, [0,  0,  0,  0,  0,  0,  180,  0]]]], [8, [[1, 1, 1, [0,  0,  0,  0,  0,  0,  185,  0]]]], [8, [[1, 1, 1, [0,  0,  0,  0,  0,  0,  190,  0]]]], [8, [[1, 1, 1, [0,  0,  0,  0,  0,  0,  195,  0]]]], [8, [[1, 1, 1, [0,  0,  0,  0,  0,  0,  200,  0]]]]]
}
```

* **equipment.json**
```json
 "409011900": {
        "name": "Ring of the Lucii",
        "compendium_id": 570,
        "compendium_shown": true,
        "rarity": 8,
        "type_id": 60,
        "type": "Accessory",
        "slot_id": 5,
        "slot": "Accessory",
        "is_twohanded": false,
        "dmg_variance": null,
        "accuracy": 0,
        "requirements": null,
        "skills": [20480, 20490, 212390, 100090, 100120],
        "effects": ["Grant 'Death' magic", "Grant 'Alterna' magic", "Grant 'Holy' passive", "Grant 'ATK +30%' passive", "Grant 'MAG +30%' passive"],
        "stats": {
            "HP": 0,
            "MP": 0,
            "ATK": 0,
            "DEF": 0,
            "MAG": 3,
            "SPR": 3,
            "element_resist": null,
            "element_inflict": null,
            "status_resist": null,
            "status_inflict": null
        },
        "price_buy": 100000,
        "price_sell": 10000,
        "icon": "item_50248.png"
    },
```