class_name BattleSystem
extends RefCounted
## Turn-based battle rules, independent of any scene so it can be unit tested
## headlessly. Turn order uses charge time (CT): every combatant fills CT at
## its speed and acts when it reaches 100, so faster units act more often.

enum Outcome { ONGOING, VICTORY, DEFEAT }

const HEAT_ON_HIT := 8
const CORRODE_FRACTION := 0.05

var party: Array[Combatant] = []
var enemies: Array[Combatant] = []
var rng := RandomNumberGenerator.new()


func _init(p_party: Array[Combatant], p_enemies: Array[Combatant], seed_value := 0) -> void:
	party = p_party
	enemies = p_enemies
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	# Stagger the opening so equal-speed monsters don't act in lockstep.
	for c in all_combatants():
		c.ct = rng.randf_range(0.0, 30.0) + c.data.speed


func all_combatants() -> Array[Combatant]:
	var all: Array[Combatant] = []
	all.append_array(party)
	all.append_array(enemies)
	return all


func living(side: Array[Combatant]) -> Array[Combatant]:
	return side.filter(func(c: Combatant) -> bool: return c.is_alive())


func allies_of(c: Combatant) -> Array[Combatant]:
	return party if c.is_player else enemies


func foes_of(c: Combatant) -> Array[Combatant]:
	return enemies if c.is_player else party


func outcome() -> Outcome:
	if living(party).is_empty():
		return Outcome.DEFEAT
	if living(enemies).is_empty():
		return Outcome.VICTORY
	return Outcome.ONGOING


## Advances time until someone is ready and returns them.
func advance_to_next_actor() -> Combatant:
	var alive := living(all_combatants())
	var actor := _next_ready(alive, func(c: Combatant) -> float: return c.ct)
	var ticks := _ticks_until_ready(actor, actor.ct)
	for c in alive:
		c.ct += c.data.speed * ticks
	actor.ct -= Combatant.CT_READY
	return actor


## Predicts the next `count` actors without changing state.
func turn_order_preview(count: int) -> Array[Combatant]:
	var alive := living(all_combatants())
	var sim := {}
	for c in alive:
		sim[c] = c.ct
	var order: Array[Combatant] = []
	while order.size() < count and not alive.is_empty():
		var actor := _next_ready(alive, func(c: Combatant) -> float: return sim[c])
		var ticks := _ticks_until_ready(actor, sim[actor])
		for c in alive:
			sim[c] += c.data.speed * ticks
		sim[actor] -= Combatant.CT_READY
		order.append(actor)
	return order


func _ticks_until_ready(c: Combatant, ct: float) -> float:
	return maxf(0.0, (Combatant.CT_READY - ct) / c.data.speed)


func _next_ready(alive: Array[Combatant], ct_of: Callable) -> Combatant:
	var best: Combatant = null
	var best_ticks := INF
	for c in alive:
		var t := _ticks_until_ready(c, ct_of.call(c))
		if t < best_ticks or (is_equal_approx(t, best_ticks) and c.data.speed > best.data.speed):
			best = c
			best_ticks = t
	return best


## Start-of-turn upkeep. Returns log lines.
func begin_turn(actor: Combatant) -> Array[String]:
	var lines: Array[String] = []
	actor.guarding = false
	if actor.data.qi_regen > 0 and actor.qi < actor.data.max_qi:
		actor.qi = mini(actor.data.max_qi, actor.qi + actor.data.qi_regen)
	if actor.statuses.has(&"corroded"):
		var dmg := maxi(1, roundi(actor.data.max_hp * CORRODE_FRACTION))
		actor.hp = maxi(0, actor.hp - dmg)
		lines.append("%s: armour etching. -%d" % [actor.display_name, dmg])
		actor.statuses[&"corroded"] -= 1
		if actor.statuses[&"corroded"] <= 0:
			actor.statuses.erase(&"corroded")
	return lines


func usable_skills(actor: Combatant) -> Array[SkillData]:
	return actor.skills.filter(func(s: SkillData) -> bool: return actor.can_use(s))


## Resolves `targets` for a skill when the caller didn't pick one.
func default_targets(actor: Combatant, skill: SkillData, picked: Combatant = null) -> Array[Combatant]:
	var targets: Array[Combatant] = []
	match skill.target:
		SkillData.Target.SELF:
			targets.append(actor)
		SkillData.Target.ALL_ENEMIES:
			targets = living(foes_of(actor))
		_:
			var foes := living(foes_of(actor))
			if picked != null and picked.is_alive():
				targets.append(picked)
			elif not foes.is_empty():
				targets.append(foes[rng.randi_range(0, foes.size() - 1)])
	return targets


## Applies a skill. Returns a result dictionary the scene uses to animate:
## { actor, skill, hits: [{target, amount, heal, killed, status}], learned, log }
func execute(actor: Combatant, skill: SkillData, targets: Array[Combatant]) -> Dictionary:
	assert(actor.can_use(skill), "%s cannot use %s" % [actor.display_name, skill.display_name])
	actor.qi -= skill.qi_cost
	actor.heat -= skill.heat_cost
	actor.add_heat(skill.heat_gain)

	var result := { "actor": actor, "skill": skill, "hits": [], "learned": null, "log": [] }
	result.log.append("%s uses %s." % [actor.display_name, skill.display_name])

	match skill.kind:
		SkillData.Kind.HEAL:
			for t in targets:
				var amount := mini(t.data.max_hp - t.hp, roundi(t.data.max_hp * skill.power))
				t.hp += amount
				result.hits.append({ "target": t, "amount": amount, "heal": true, "killed": false, "status": &"" })
		SkillData.Kind.GUARD:
			actor.guarding = true
			actor.qi = mini(actor.data.max_qi, actor.qi + roundi(actor.data.max_qi * 0.15))
		_:
			for t in targets:
				result.hits.append(_hit(actor, skill, t))

	_try_copy(actor, skill, result)
	return result


func _hit(actor: Combatant, skill: SkillData, target: Combatant) -> Dictionary:
	var physical := skill.kind == SkillData.Kind.PHYSICAL
	var offence := float(actor.data.attack if physical else actor.data.qi_power)
	var mitigation := float(target.data.defense if physical else target.data.resistance)
	var raw := skill.power * offence * 100.0 / (100.0 + mitigation * 2.0)
	var amount := maxi(1, roundi(raw * rng.randf_range(0.9, 1.1)))
	if target.guarding:
		amount = maxi(1, roundi(amount * 0.5))
	target.hp = maxi(0, target.hp - amount)
	target.add_heat(HEAT_ON_HIT)
	var status: StringName = &""
	if skill.inflicts != &"" and target.is_alive() and rng.randf() < skill.inflict_chance:
		target.statuses[skill.inflicts] = skill.inflict_turns
		status = skill.inflicts
	return { "target": target, "amount": amount, "heal": false, "killed": not target.is_alive(), "status": status }


## Baihua's cognitive core maps any copyable technique used against her
## (Chapter Seventeen) and adds an optimised version to her skill list.
func _try_copy(actor: Combatant, skill: SkillData, result: Dictionary) -> void:
	if not skill.copyable:
		return
	for observer in living(foes_of(actor)):
		if observer.data.can_copy and not observer.knows(skill.id):
			var copy := skill.make_optimized_copy()
			observer.skills.insert(maxi(0, observer.skills.size() - 1), copy)
			result.learned = copy
			result.log.append("Cognitive core mapped %s. Optimised: +10%% output, -15%% qi." % skill.display_name)


## Simple monster AI: favour special techniques, otherwise basic attack.
func choose_enemy_action(actor: Combatant) -> Dictionary:
	var options := usable_skills(actor)
	var skill: SkillData = options[0]
	if options.size() > 1 and rng.randf() < 0.4:
		skill = options[rng.randi_range(1, options.size() - 1)]
	return { "skill": skill, "targets": default_targets(actor, skill) }


func total_reward() -> int:
	var total := 0
	for e in enemies:
		total += e.data.reward_stones
	return total


## Opening line in Baihua's diagnostic voice.
func threat_assessment() -> String:
	var enemy_power := 0
	for e in enemies:
		enemy_power += e.data.max_hp * e.data.attack
	var own_power := 0
	for p in party:
		own_power += p.data.max_hp * p.data.attack
	var ratio := float(enemy_power) / maxf(1.0, own_power)
	if ratio < 0.4:
		return "Threat assessment: minimal."
	if ratio < 0.9:
		return "Threat assessment: moderate. Proceed with precision."
	return "Threat assessment: significant. Regulator override may be required."
