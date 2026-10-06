class_name ScheduledHit
extends RefCounted

## One hit waiting on the timeline. Its effect handler fills in the cast-time part
## (target, frame, amount, flags); the engine fills in the results when it lands. The
## hit-time hooks read and change it: a dodge cancels it, mitigation lowers the amount.

var action: BattleAction = null
var effect: SkillEffect = null
var handler: EffectHandler = null
var actor_id: int = -1
var target_id: int = -1
## Absolute frame the hit lands on.
var frame: int = 0
## 0-based index of this hit among the effect's hits on this target.
var hit_index: int = 0
var hit_count: int = 1
## The hand that makes the hit: DualWield.RIGHT, or LEFT for a dual wielder's second
## swing.
var swing: int = 0
## This hit's share of the amount computed at cast time, before hit-time terms.
var amount: float = 0.0
## A DamageFormula.Kind value, for damage hits.
var damage_kind: int = 0
## A BattleSkill.ATTACK_* value: what dodge, mitigation and cover see.
var attack_type: int = BattleSkill.ATTACK_UNKNOWN
## 1-based element ids carried by the hit.
var elements: PackedInt32Array = PackedInt32Array()
## Whether the hit counts toward the target's chain, and whether the chain multiplier
## raises its damage. Percent and fixed damage build chains without the bonus.
var builds_chain: bool = true
var takes_chain_bonus: bool = true
## Percent of the damage dealt that heals the attacker (drain).
var drain_pct: int = 0
## Counts toward the actor's weapon inflicts on the target (WeaponInflict).
var weapon_inflicts: bool = false
## Data only the hit's handler reads (the status to apply, the pool to restore, ...).
var payload: Dictionary = {}

# --- Results ---

var cancelled: bool = false
var cancel_reason: StringName = &""
## Got past cancellation and evasion to a living target (damage hits).
var landed: bool = false
## Damage dealt after hit-time terms (can exceed the target's remaining HP).
var final_amount: int = 0
## Part of final_amount a barrier absorbed.
var absorbed: int = 0
var chain_count: int = 0
## Chain multiplier in percent (110 = 1.1x).
var chain_percent: int = 100
## A spark chain (the same frame as the previous hit on the target), and the elements
## shared with that hit (an elemental chain when above 0).
var chain_spark: bool = false
var chain_shared_elements: int = 0
var killed: bool = false
