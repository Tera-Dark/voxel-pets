--!nonstrict
-- Turns (pet definition + owned-instance progression + relics) into a Combatant the
-- simulator can run. Everything the player can influence enters here: out-of-run
-- progression (level/stars/evolution/variant) and in-run expedition relics.
local Pets = require("../Config/Pets")
local Skills = require("../Config/Skills")
local Relics = require("../Config/Relics")
local Formulas = require("../Config/Formulas")
local Constants = require("../Config/Constants")

local Builder = {}

local function defaultMods()
	return {
		cooldownMult = 1,
		elementMode = "normal",
		canInterrupt = false,
		skillBurnStacks = 0,
		skillLifestealPct = 0,
		basicChillChance = 0,
		healToShieldPct = 0,
		firstSkillFree = false,
		startHpLossPct = 0,
		startShieldPct = 0,
		-- pet passives
		critVsBurning = 0,
		chillAttackerChance = 0,
		reviveOnce = false,
		executioner = false,
		hardening = false,
	}
end

local PASSIVES = {
	Kindled = function(c)
		c.mods.critVsBurning = 0.15
	end,
	SlickSkin = function(c)
		c.mods.chillAttackerChance = 0.10
	end,
	RootedCalm = function(c)
		c.def = math.floor(c.def * 1.15)
	end,
	SecondDawn = function(c)
		c.mods.reviveOnce = true
	end,
	Executioner = function(c)
		c.mods.executioner = true
	end,
	Hardening = function(c)
		c.mods.hardening = true
	end,
	DeepShield = function(c)
		c.mods.startShieldPct = 0.10
	end,
}

local function applyRelic(c, relic)
	local m = c.mods
	if relic.statMult then
		for stat, mult in relic.statMult do
			if stat == "crit" then
				c.crit += mult
			elseif stat == "hp" then
				c.maxHp = math.floor(c.maxHp * mult)
			else
				c[stat] = math.floor(c[stat] * mult)
			end
		end
	end
	if relic.cooldownMult then
		m.cooldownMult *= relic.cooldownMult
	end
	if relic.elementMode then
		m.elementMode = relic.elementMode
	end
	if relic.canInterrupt then
		m.canInterrupt = true
	end
	if relic.onSkillHit then
		m.skillBurnStacks += relic.onSkillHit.burnStacks or 0
		m.skillLifestealPct += relic.onSkillHit.lifestealPct or 0
	end
	if relic.onBasicHit then
		m.basicChillChance += relic.onBasicHit.chillChance or 0
	end
	if relic.healToShieldPct then
		m.healToShieldPct += relic.healToShieldPct
	end
	if relic.firstSkillFree then
		m.firstSkillFree = true
	end
	if relic.startHpLossPct then
		m.startHpLossPct += relic.startHpLossPct
	end
end

-- instance: { petId, level?, stars?, evolution?, variant? }
-- opts: { side = "A"|"B", slot = 1..5, relics = { relicId }, extraMult = number?, displayName = string? }
function Builder.build(instance, opts)
	local def = Pets[instance.petId]
	assert(def, "unknown pet " .. tostring(instance.petId))
	opts = opts or {}
	local side, slot = opts.side or "A", opts.slot or 1
	local stats = Formulas.finalStats(def, instance, opts.extraMult)

	local c = {
		uid = side .. slot,
		side = side,
		slot = slot,
		petId = def.id,
		name = opts.displayName or def.displayName,
		element = opts.elementOverride or def.element, -- override is for balance tooling only
		role = def.role,
		level = instance.level or 1,
		maxHp = stats.hp,
		hp = stats.hp,
		atk = stats.atk,
		def = stats.def,
		spd = stats.spd,
		crit = stats.crit,
		skills = {},
		statuses = {},
		shield = 0,
		shieldExpiresAt = 0,
		attackTimer = 0,
		charging = nil,
		alive = true,
		revived = false,
		usedFirstSkill = false,
		hardeningSteps = 0,
		mods = defaultMods(),
		relics = {},
	}

	if def.skill then
		local skillDef = Skills[def.skill]
		assert(skillDef, "unknown skill " .. tostring(def.skill))
		table.insert(c.skills, { id = def.skill, def = skillDef, cooldownLeft = 0, readyFor = 0 })
	end

	if def.passive and PASSIVES[def.passive] then
		PASSIVES[def.passive](c)
	end

	for _, relicId in opts.relics or {} do
		local relic = Relics[relicId]
		assert(relic, "unknown relic " .. tostring(relicId))
		applyRelic(c, relic)
		table.insert(c.relics, relicId)
	end

	c.baseDef = c.def
	c.maxHp = math.max(1, c.maxHp)
	c.hp = c.maxHp
	c.power = Formulas.power({ hp = c.maxHp, atk = c.atk, def = c.def, spd = c.spd })
	return c
end

-- Convenience for PvE: a wild pet scaled to zone/stage.
function Builder.buildEnemy(petId: string, zone: number, stage: number, opts)
	opts = opts or {}
	opts.side = opts.side or "B"
	local def = Pets[petId]
	local eliteMult = (def and def.elite) and Constants.ELITE_STAT_MULT or 1
	opts.extraMult = Formulas.enemyScale(zone, stage) * eliteMult * (opts.extraMult or 1)
	local level = (zone - 1) * 10 + stage
	return Builder.build({ petId = petId, level = level }, opts)
end

return Builder
