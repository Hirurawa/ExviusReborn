class_name BattleRules
extends RefCounted

## Tunable numbers and switches for one battle. Defaults reproduce the old engine's
## constants where it had them. None of these values is a confirmed FFBE rule unless its
## comment says so; the open questions behind several of them are listed in
## BATTLE-ENGINE-HANDOVER.md section 10. Tests override fields directly.

## Simulation rate. attackFrames and sprite delays are authored in 1/60 s.
const TICKS_PER_SECOND: int = 60

# --- Chains ---
# Chain multipliers are whole percentages (130 = 1.3x) so repeated steps add up
# exactly: ten float steps of 0.3 come to 3.999..., which would floor 100 damage at
# the cap to 399.

## A hit continues the target's chain when it lands at most this many frames after the
## previous hit on that target (wiki: 0 to 20).
var chain_window_frames: int = 20
## Added to the chain multiplier by a normal chain, a hit that continues the chain one
## or more frames after the previous hit, in percent (wiki: 10). The old engine used 30.
var chain_step_pct: int = 10
## Added instead of chain_step_pct by a spark chain, a hit on the same frame as the
## previous hit, in percent (wiki: 40). Hits of actions started on the same frame land
## in party order (see BattleTimeline), so the first of them is a normal chain.
var chain_spark_step_pct: int = 40
## Extra step per element the hit shares with the previous hit (elemental chain), on top
## of the normal or spark step, in percent (wiki: 20). 0 turns it off.
var chain_element_step_pct: int = 20
## Ceiling of the chain multiplier one hit gets, in percent (wiki: the modifier caps at
## 300%, so 4x). Chain cap passives raise it for the unit that has them
## (CombatantPassives.chain_cap_raise), up to chain_cap_ceiling_pct.
var chain_cap_pct: int = 400
## The highest a raised cap goes, and how far a target's chain itself grows, in percent
## (wiki: cap passives raise the modifier cap by up to 200%, to 500%, so 6x). The chain
## keeps growing past chain_cap_pct whoever hits; each hit takes the chain up to its own
## attacker's cap ("This increased cap works even if the unit use an existing chain
## provided by other units without these passives").
var chain_cap_ceiling_pct: int = 600
## A hit from the same combatant as the previous hit on that target starts a new chain
## instead of extending the old one (old engine rule).
var chain_same_source_breaks: bool = true
## Whether enemy hits build chains on party members. Confirmed that they do; it is rare
## but can matter. Same-source hits still break the chain, so it takes hits from two
## enemies landing within the window.
var enemy_hits_chain: bool = true

# --- Damage ---

## Final variance: a random damage multiplier rolled once per target at cast time, in
## steps of 0.01 between these two. Wiki: 0.85 to 1.0, averaging 0.925. Equal values
## skip the roll.
var damage_variance_min: float = 0.85
var damage_variance_max: float = 1.0
## Weapon variance: every formula damage (physical, magic, hybrid, DEF- and SPR-based,
## evoke) is multiplied by a whole percent rolled between the attacker's weapon's
## dmgVariance values (Combatant.weapon_variance_min/max), once per target at cast time
## (the user's rules, 2026-10-02). Off, the term is 1.0.
var weapon_variance: bool = true
## Level correction: formula damage is multiplied by 1 + the attacker's level / 100
## (wiki). It applies to enemies as well as the party (the user's rule, 2026-09-30).
var level_correction: bool = true
## Multiplier on all damage taken while defending. Confirmed: defending halves all
## incoming damage. The old engine set the flag and never read it.
var defend_damage_multiplier: float = 0.5
## Cap on a unit's passive killer percent against one race, before its passive raises
## (op 105) and before active killer buffs, which go on top (the user's rule,
## 2026-09-30: 300% per race, passives and equipment together, applied per race before
## the average over the target's races).
var passive_killer_cap_pct: int = 300

# --- Statuses ---

## When a status meets one with the same stack key (the same buff, break or imperil
## of the same stat or element), false lets the newer replace it and true keeps the
## stronger. Unconfirmed which one FFBE does.
var keep_stronger_status: bool = false
## Turns a status lasts when its data says 0 (27% of breaks, mostly on monster
## skills). What 0 means is unconfirmed; 1 lasts to the end of the current turn.
var zero_turn_status_turns: int = 1

# --- Ailments ---
# What each ailment does lives in engine/behaviors/. The wiki's rules, and the user's
# choices where the wiki gives no number (2026-09-29).

## Poison damage at the end of each turn, in percent of max HP (wiki). It can KO.
var poison_max_hp_pct: int = 10
## Chance that a blinded combatant's physical or hybrid attack misses a target, rolled
## once per target at cast time.
var blind_miss_pct: int = 30
## Disease lowers ATK, DEF, MAG and SPR by this percent of their raw base, adding up
## with breaks (wiki: 10%).
var disease_stat_pct: int = 10
## Turns a sleep lasts on a party member (wiki: 3). Counted like every status: the turn
## it lands in is the first, so a sleep from the enemy phase costs two player phases.
var party_sleep_turns: int = 3
## Chance percent that an enemy shakes off each ailment at the start of each of its
## turns (wiki: "varied duration, with a chance to recover at the start of their turn").
## The data has no per-monster value; 25 is the user's starting point. Stop, charm and
## berserk last their data's turns instead.
var enemy_ailment_recovery_pct: int = 25

# --- Cover ---

## Whether a disabled combatant (asleep, paralyzed, stopped, charmed, petrified) can
## still trigger its cover. Unconfirmed; off keeps them out, as they cannot act.
var disabled_units_cover: bool = false

# --- Timing ---

## Frames between an action starting and its attack frames counting, keyed by move
## type (int). Missing types add nothing, which matches the old engine.
var move_offset_frames: Dictionary = {}
## Frames an enemy waits after its previous action's last hit before acting again.
var enemy_action_gap_frames: int = 20
## Least number of frames one enemy action occupies, so short actions stay readable.
var enemy_action_min_span_frames: int = 90
## Frames from the start of one cast to the start of the next: a dual wielder's left
## swing after its right swing, and each pick of a multicast after the one before. The
## user's rule (2026-10-05): the wiki's multicast cast delay, 39 frames from the start of
## the previous cast, taken as fixed while unit motions are not modelled (the wiki waits
## for a motion longer than 39 frames to finish).
var cast_gap_frames: int = 39
## Frames between the last hit of one reaction in the opening phase (a counter, a
## battle-start or turn-start cast) and the start of the next, which run one at a time.
## Unconfirmed; 20 matches enemy_action_gap_frames and keeps counters from chaining with
## each other (a chain needs the next hit within chain_window_frames).
var reaction_gap_frames: int = 20

# --- Limit gauge ---

## Chance that a damaging party hit on an enemy drops a limit crystal, and the gauge it
## gives a random living party member (hundredths of a crystal). Old engine values.
var lb_crystal_drop_chance: float = 0.2
var lb_crystal_amount: int = 100

# --- Esper gauge ---

## Orbs that fill the party's esper (evocation) gauge. The party shares one gauge; a unit
## with an esper can evoke it only while the gauge is full, and evoking empties it (the
## user's rules, 2026-10-02). 10 is also what the data's "fill evocation gauge to max"
## skills fill (opcode 32 with 10,10).
var esper_gauge_max: int = 10
## Chance that a damaging party hit on an enemy drops one orb into the gauge. The real
## number is unknown; 0.1 is the user's starting point (2026-10-02).
var esper_orb_drop_chance: float = 0.1
## Cap on EVO MAG in percent (wiki: "caps at 300%"). Evoke damage is multiplied by
## 1 + EVO MAG / 100.
var evo_mag_cap_pct: int = 300
## Cap on the evoke damage boost passives in percent (wiki: "Caps at 4 (base 100% +
## 300%)").
var evoke_boost_cap_pct: int = 300
## MAG's share in percent of the evoke formula for the espers' own attacks (79, 80, 94),
## whose data has no ratio; SPR takes the rest. The wiki's default, 50:50, until a
## datapoint says otherwise (the user's rule, 2026-10-02).
var esper_attack_mag_ratio_pct: int = 50

# --- Jumps ---

## Cap on jump damage% (passive 17) in percent; the wiki: "Jump damage% stacks additively
## and hard caps at 800%". Its own multiplier on landing damage (the user's rule,
## 2026-10-06).
var jump_damage_cap_pct: int = 800
## The flat variance a two-handed jumper's landing rolls, in whole percent; the wiki:
## "two-handed jump damage will now be calculated either based on the equipment's weapon
## damage variance or at a flat rate of 2.50~2.80, whichever is higher". Both are rolled
## and the higher kept.
var jump_two_handed_variance_min: int = 250
var jump_two_handed_variance_max: int = 280


## Frames added before an action's attack frames for a skill with this move type.
func move_offset(move_type: int) -> int:
	return int(move_offset_frames.get(move_type, 0))
