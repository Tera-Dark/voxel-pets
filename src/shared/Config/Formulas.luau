--!nonstrict
-- Pure math shared by server, client (display) and the simulator.
local Constants = require("./Constants")
local Rarities = require("./Rarities")

local Formulas = {}

function Formulas.levelMult(level: number): number
	return 1 + Constants.LEVEL_STAT_PER_LEVEL * (level - 1)
end

function Formulas.starMult(stars: number): number
	return 1 + Constants.STAR_STAT_PER_STAR * (stars - 1)
end

function Formulas.evolutionMult(stage: number): number
	return Constants.EVOLUTION_MULT[stage] or 1
end

-- Multiplier applied to HP/ATK/DEF for an owned pet instance.
-- instance = { level, stars, evolution, variant }
function Formulas.growthMult(rarity: string, instance): number
	return Rarities.StatMult[rarity]
		* Formulas.levelMult(instance.level or 1)
		* Formulas.evolutionMult(instance.evolution or 1)
		* Formulas.starMult(instance.stars or 1)
		* Rarities.VariantMult[instance.variant or "Normal"]
end

-- Final stat block for a pet definition + instance (+ optional extra multiplier, e.g. zone scaling).
function Formulas.finalStats(petDef, instance, extraMult: number?)
	local m = Formulas.growthMult(petDef.rarity, instance) * (extraMult or 1)
	local b = petDef.baseStats
	return {
		hp = math.floor(b.hp * m),
		atk = math.floor(b.atk * m),
		def = math.floor(b.def * m),
		spd = b.spd,
		crit = b.crit,
	}
end

-- Headline "Power" number shown in UI and used for matchmaking. Uses final stats.
function Formulas.power(stats): number
	return math.floor(stats.hp / 10 + stats.atk * 2 + stats.def * 1.5 + stats.spd * 0.5)
end

-- Scale-invariant mitigation: doubling both sides' stats leaves the fight shape unchanged.
function Formulas.mitigation(def: number, attackerAtk: number): number
	return def / (def + Constants.MITIGATION_K * attackerAtk)
end

-- PvE enemy stat multiplier for zone/stage (1-based).
function Formulas.enemyScale(zone: number, stage: number): number
	return Constants.WILD_STAT_MULT
		* Constants.ZONE_STAT_MULT ^ (zone - 1)
		* Constants.STAGE_STAT_MULT ^ (stage - 1)
end

function Formulas.xpForLevel(level: number): number
	return math.floor(50 * level ^ 1.8)
end

-- Compact number formatting: 1234 -> "1.23K"
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
function Formulas.formatNumber(n: number): string
	if n < 1000 then
		return tostring(math.floor(n))
	end
	local idx = 1
	while n >= 1000 and idx < #SUFFIXES do
		n /= 1000
		idx += 1
	end
	return string.format(n >= 100 and "%.0f%s" or "%.2f%s", n, SUFFIXES[idx])
end

return Formulas
