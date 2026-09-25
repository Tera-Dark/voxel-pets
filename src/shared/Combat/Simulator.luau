--!nonstrict
-- Deterministic, fully automatic battle simulator.
--
-- Given two teams of combatants (see Builder) and a seed, produces the same result and the
-- same event list every time, on every platform. The server runs it once per battle and
-- persists the result; clients only *play back* the events. "Skip" = jump to the result.
--
-- Supports N v M (up to Constants.MAX_TEAM_SLOTS per side); P0 only exercises 1v1.
local Constants = require("../Config/Constants")
local Elements = require("../Config/Elements")
local StatusEffects = require("../Config/StatusEffects")
local Formulas = require("../Config/Formulas")
local Rng = require("./Rng")

local Simulator = {}

local DEBUFFS = { Burn = true, Chill = true, Root = true, Blind = true, Vulnerable = true }

-- options: { seed: number, teamA: {Combatant}, teamB: {Combatant}, maxTime: number?, recordEvents: boolean? }
function Simulator.run(options)
	local rng = Rng.new(options.seed or 1)
	local dt = Constants.TICK_SECONDS
	local maxTime = options.maxTime or Constants.MAX_BATTLE_SECONDS
	local record = options.recordEvents ~= false
	local t = 0

	local all = {}
	for _, c in options.teamA do
		table.insert(all, c)
	end
	for _, c in options.teamB do
		table.insert(all, c)
	end

	local events = {}
	local summary = { damage = { A = 0, B = 0 }, skillCasts = { A = 0, B = 0 }, interrupts = 0 }

	local function emit(kind, data)
		if not record then
			return
		end
		data = data or {}
		data.t = math.floor(t * 100 + 0.5) / 100
		data.type = kind
		table.insert(events, data)
	end

	-- ---------------------------------------------------------------- helpers
	local function aliveOn(side)
		local list = {}
		for _, c in all do
			if c.side == side and c.alive then
				table.insert(list, c)
			end
		end
		return list
	end

	local function pickTarget(c)
		local enemies = aliveOn(c.side == "A" and "B" or "A")
		return enemies[1] -- slot order; taunts / rows come with multi-slot teams
	end

	local function hasStatus(c, id)
		return c.statuses[id] ~= nil
	end

	local function hasDebuff(c)
		for id in c.statuses do
			if DEBUFFS[id] then
				return true
			end
		end
		return false
	end

	local function attackSpeedMult(c)
		local m = 1
		for id in c.statuses do
			local def = StatusEffects[id]
			if def.attackSpeedMult then
				m *= def.attackSpeedMult
			end
		end
		return m
	end

	local function chargeProgress(c)
		if not c.charging then
			return 0
		end
		return c.charging.elapsed / c.charging.castTime
	end

	local function applyStatus(target, id, source, stacks)
		if not target.alive then
			return
		end
		if target.mods.immuneControl and (id == "Root" or id == "Blind") then
			emit("Immune", { dst = target.uid, status = id })
			return
		end
		local def = StatusEffects[id]
		local inst = target.statuses[id]
		if inst then
			inst.remaining = def.duration
			if def.stackable then
				inst.stacks = math.min(def.maxStacks, inst.stacks + (stacks or 1))
			end
			inst.sourceAtk = source and source.atk or inst.sourceAtk
		else
			target.statuses[id] = {
				remaining = def.duration,
				stacks = def.stackable and math.min(def.maxStacks, stacks or 1) or 1,
				tickAcc = 0,
				sourceAtk = source and source.atk or 0,
			}
		end
		emit("Status", {
			src = source and source.uid,
			dst = target.uid,
			status = id,
			stacks = target.statuses[id].stacks,
		})
	end

	local function addShield(c, amount, source)
		amount = math.floor(amount)
		if amount <= 0 then
			return
		end
		c.shield += amount
		c.shieldExpiresAt = t + StatusEffects.Shield.duration
		emit(
			"Shield",
			{ src = source and source.uid or c.uid, dst = c.uid, amount = amount, total = c.shield }
		)
	end

	local function heal(c, amount, source)
		if not c.alive then
			return
		end
		amount = math.floor(math.min(amount, c.maxHp - c.hp))
		if amount > 0 then
			c.hp += amount
			emit(
				"Heal",
				{ src = source and source.uid or c.uid, dst = c.uid, amount = amount, hp = c.hp }
			)
		end
		if c.mods.healToShieldPct > 0 then
			addShield(c, amount * c.mods.healToShieldPct, source)
		end
	end

	local function cleanse(c)
		for id in c.statuses do
			if DEBUFFS[id] then
				c.statuses[id] = nil
			end
		end
		emit("Cleanse", { dst = c.uid })
	end

	local function onDeath(c, killer)
		if c.mods.reviveOnce and not c.revived then
			c.revived = true
			c.hp = math.floor(c.maxHp * 0.3)
			cleanse(c)
			emit("Revive", { dst = c.uid, hp = c.hp })
			return
		end
		c.alive = false
		c.charging = nil
		emit("Death", { dst = c.uid, src = killer and killer.uid })
	end

	local function updateHardening(c)
		if not c.mods.hardening then
			return
		end
		local steps = math.floor((1 - c.hp / c.maxHp) * 10)
		if steps > c.hardeningSteps then
			c.hardeningSteps = steps
			c.def = math.floor(c.baseDef * (1 + 0.08 * steps))
		end
	end

	-- Applies raw damage (already multiplied) through shield then HP. Returns amount absorbed+dealt.
	local function applyRawDamage(dst, amount, src, meta)
		amount = math.max(0, math.floor(amount))
		local absorbed = 0
		if dst.shield > 0 then
			absorbed = math.min(dst.shield, amount)
			dst.shield -= absorbed
			amount -= absorbed
		end
		dst.hp -= amount
		if dst.hp < 0 then
			dst.hp = 0
		end
		meta = meta or {}
		meta.src = src and src.uid
		meta.dst = dst.uid
		meta.amount = amount
		meta.absorbed = absorbed
		meta.hp = dst.hp
		emit("Damage", meta)
		if src then
			summary.damage[src.side] += amount + absorbed
		end
		updateHardening(dst)
		if dst.hp <= 0 then
			onDeath(dst, src)
		end
		return amount + absorbed
	end

	-- ctx: { isSkill: boolean, interrupt: boolean }
	local function dealDamage(src, dst, mult, ctx)
		if not dst.alive then
			return 0
		end
		local mitigation = Formulas.mitigation(dst.def, src.atk)
		local base = src.atk * mult * (1 - mitigation)
		local element = Elements.multiplier(
			src.element,
			dst.element,
			src.mods.elementMode,
			dst.mods.elementMode
		)

		local critChance = src.crit
		if src.mods.critVsBurning > 0 and hasStatus(dst, "Burn") then
			critChance += src.mods.critVsBurning
		end
		local isCrit = rng:chance(critChance)
		local critMult = isCrit and Constants.CRIT_MULT or 1
		local vuln = hasStatus(dst, "Vulnerable") and StatusEffects.Vulnerable.damageTakenMult or 1
		local execute = (src.mods.executioner and dst.hp / dst.maxHp < 0.3) and 1.5 or 1
		local interrupt = ctx.interrupt and Constants.INTERRUPT_MULT or 1
		local variance = rng:range(1 - Constants.DAMAGE_VARIANCE, 1 + Constants.DAMAGE_VARIANCE)
		local enrage = 1
		if t > Constants.ENRAGE_START_SECONDS then
			local steps = math.floor(
				(t - Constants.ENRAGE_START_SECONDS) / Constants.ENRAGE_STEP_SECONDS
			) + 1
			enrage = 1 + steps * Constants.ENRAGE_STEP_MULT
		end

		local total = base * element * critMult * vuln * execute * interrupt * variance * enrage
		return applyRawDamage(dst, total, src, {
			crit = isCrit or nil,
			element = element ~= 1 and element or nil,
			skill = ctx.isSkill or nil,
			interrupt = ctx.interrupt or nil,
		})
	end

	local function castSkill(c, skill, target)
		local def = skill.def
		local interrupt = false
		if
			target.charging
			and c.mods.canInterrupt
			and chargeProgress(target) >= Constants.INTERRUPT_WINDOW
		then
			interrupt = true
			local interrupted = target.charging.skill
			interrupted.cooldownLeft = interrupted.def.cooldown * target.mods.cooldownMult
			interrupted.readyFor = 0
			target.charging = nil
			summary.interrupts += 1
			emit("Interrupt", { src = c.uid, dst = target.uid, skill = interrupted.id })
		end
		emit("Skill", { src = c.uid, dst = target.uid, skill = skill.id })
		summary.skillCasts[c.side] += 1

		local dealt = 0
		for _, effect in def.effects do
			if effect.type == "Damage" then
				dealt += dealDamage(
					c,
					target,
					effect.mult,
					{ isSkill = true, interrupt = interrupt }
				)
			elseif effect.type == "Status" then
				applyStatus(
					effect.target == "Self" and c or target,
					effect.status,
					c,
					effect.stacks
				)
			elseif effect.type == "Heal" then
				heal(c, c.maxHp * effect.pctMaxHp, c)
			elseif effect.type == "Shield" then
				addShield(c, c.maxHp * effect.pctMaxHp, c)
			elseif effect.type == "Cleanse" then
				cleanse(c)
			end
		end

		if dealt > 0 then
			if c.mods.skillBurnStacks > 0 then
				applyStatus(target, "Burn", c, c.mods.skillBurnStacks)
			end
			if c.mods.skillLifestealPct > 0 then
				heal(c, dealt * c.mods.skillLifestealPct, c)
			end
		end

		local cooldown = def.cooldown * c.mods.cooldownMult
		if c.mods.firstSkillFree and not c.usedFirstSkill then
			cooldown = 0
		end
		c.usedFirstSkill = true
		skill.cooldownLeft = cooldown
		skill.readyFor = 0
	end

	local function triggerSatisfied(c, skill, target)
		if
			c.mods.canInterrupt
			and target.charging
			and chargeProgress(target) >= Constants.INTERRUPT_WINDOW
		then
			return true
		end
		local trig = skill.def.trigger or { kind = "Ready" }
		local ok = false
		if trig.kind == "Ready" then
			ok = true
		elseif trig.kind == "SelfHpBelow" then
			ok = c.hp / c.maxHp < trig.value
		elseif trig.kind == "TargetHpBelow" then
			ok = target.hp / target.maxHp < trig.value
		elseif trig.kind == "TargetHasStatus" then
			ok = hasStatus(target, trig.status)
		elseif trig.kind == "SelfHasDebuff" then
			ok = hasDebuff(c)
		end
		if not ok and skill.readyFor >= (trig.maxWait or Constants.DEFAULT_TRIGGER_MAX_WAIT) then
			ok = true
		end
		return ok
	end

	local function basicAttack(c, target)
		if hasStatus(c, "Blind") and rng:chance(StatusEffects.Blind.basicMissChance) then
			emit("Miss", { src = c.uid, dst = target.uid })
			return
		end
		local dealt = dealDamage(c, target, 1, { isSkill = false })
		if dealt > 0 and target.alive then
			if c.mods.basicChillChance > 0 and rng:chance(c.mods.basicChillChance) then
				applyStatus(target, "Chill", c)
			end
			if
				target.mods.chillAttackerChance > 0 and rng:chance(target.mods.chillAttackerChance)
			then
				applyStatus(c, "Chill", target)
			end
		end
	end

	local function tickStatuses(c)
		if c.shield > 0 and t >= c.shieldExpiresAt then
			c.shield = 0
			emit("ShieldExpired", { dst = c.uid })
		end
		for id, inst in c.statuses do
			local def = StatusEffects[id]
			inst.remaining -= dt
			if def.tickEvery then
				inst.tickAcc += dt
				while inst.tickAcc >= def.tickEvery - 1e-9 and c.alive do
					inst.tickAcc -= def.tickEvery
					if id == "Burn" then
						local dmg = inst.stacks * def.damagePerStackPctOfSourceAtk * inst.sourceAtk
						applyRawDamage(c, dmg, nil, { status = "Burn" })
					elseif id == "Regen" then
						heal(c, c.maxHp * def.healPctMaxHp, c)
					end
				end
			end
			if inst.remaining <= 1e-9 then
				c.statuses[id] = nil
				emit("StatusEnd", { dst = c.uid, status = id })
			end
		end
	end

	local function act(c)
		local target = pickTarget(c)
		if not target then
			return
		end

		if c.charging then
			c.charging.elapsed += dt
			if c.charging.elapsed >= c.charging.castTime - 1e-9 then
				local skill = c.charging.skill
				c.charging = nil
				castSkill(c, skill, target)
			end
			return
		end

		for _, skill in c.skills do
			if skill.cooldownLeft > 0 then
				skill.cooldownLeft = math.max(0, skill.cooldownLeft - dt)
			else
				skill.readyFor += dt
			end
		end

		for _, skill in c.skills do
			if skill.cooldownLeft <= 0 and triggerSatisfied(c, skill, target) then
				if (skill.def.castTime or 0) > 0 then
					c.charging = { skill = skill, elapsed = 0, castTime = skill.def.castTime }
					emit(
						"ChargeStart",
						{ src = c.uid, skill = skill.id, castTime = skill.def.castTime }
					)
				else
					castSkill(c, skill, target)
				end
				return
			end
		end

		if hasStatus(c, "Root") then
			return
		end
		c.attackTimer += dt * (c.spd / 100) * attackSpeedMult(c)
		while c.attackTimer >= 1 do
			c.attackTimer -= 1
			basicAttack(c, target)
			if not target.alive or not c.alive then
				break
			end
		end
	end

	local function sideDone(side)
		return #aliveOn(side) == 0
	end

	-- ---------------------------------------------------------------- battle start
	local sideAFirst = rng:chance(0.5)
	local function actOrder(a, b)
		local sa, sb = a.spd * attackSpeedMult(a), b.spd * attackSpeedMult(b)
		if sa ~= sb then
			return sa > sb
		end
		if a.side ~= b.side then
			return (a.side == "A") == sideAFirst
		end
		return a.slot < b.slot
	end

	emit("BattleStart", { seed = options.seed, a = #options.teamA, b = #options.teamB })
	for _, c in all do
		if c.mods.startHpLossPct > 0 then
			applyRawDamage(c, c.maxHp * c.mods.startHpLossPct, nil, { status = "Curse" })
		end
		if c.mods.startShieldPct > 0 then
			addShield(c, c.maxHp * c.mods.startShieldPct, c)
		end
	end

	-- ---------------------------------------------------------------- main loop
	local ticks = 0
	local winner
	while t < maxTime - 1e-9 do
		t += dt
		ticks += 1
		for _, c in all do
			if c.alive then
				tickStatuses(c)
			end
		end
		if sideDone("A") or sideDone("B") then
			break
		end

		local order = {}
		for _, c in all do
			if c.alive then
				table.insert(order, c)
			end
		end
		table.sort(order, actOrder)
		for _, c in order do
			if c.alive then
				act(c)
			end
		end
		if sideDone("A") or sideDone("B") then
			break
		end
	end

	local function hpFraction(side)
		local sum, n = 0, 0
		for _, c in all do
			if c.side == side then
				sum += c.alive and c.hp / c.maxHp or 0
				n += 1
			end
		end
		return n > 0 and sum / n or 0
	end

	local fracA, fracB = hpFraction("A"), hpFraction("B")
	local timedOut = false
	if sideDone("B") and not sideDone("A") then
		winner = "A"
	elseif sideDone("A") and not sideDone("B") then
		winner = "B"
	else
		timedOut = not (sideDone("A") and sideDone("B"))
		winner = fracA > fracB and "A" or (fracB > fracA and "B" or "Draw")
	end

	emit("BattleEnd", { winner = winner, duration = t, timedOut = timedOut })
	return {
		winner = winner,
		duration = math.floor(t * 10 + 0.5) / 10,
		ticks = ticks,
		timedOut = timedOut,
		hpLeft = { A = fracA, B = fracB },
		summary = summary,
		events = events,
	}
end

return Simulator
