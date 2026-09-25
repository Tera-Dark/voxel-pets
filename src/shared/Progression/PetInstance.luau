--!nonstrict
-- Owned-pet progression rules: XP/levels, paid level-ups, evolution, stars, dismantle, fusion.
local Pets = require("../Config/Pets")
local Rarities = require("../Config/Rarities")
local Constants = require("../Config/Constants")
local Formulas = require("../Config/Formulas")

local PetInstance = {}

PetInstance.SHARDS_BY_RARITY = {
	Common = 5,
	Uncommon = 10,
	Rare = 20,
	Epic = 40,
	Legendary = 80,
	Mythic = 150,
	Secret = 400,
}
PetInstance.FUSE_COUNT = 5
PetInstance.NEXT_VARIANT = { Normal = "Golden", Golden = "Rainbow", Rainbow = "DarkMatter" }

function PetInstance.new(petId: string, uid: string, now: number?)
	return {
		uid = uid,
		petId = petId,
		level = 1,
		xp = 0,
		stars = 1,
		evolution = 1,
		variant = "Normal",
		hatchedAt = now or os.time(),
		locked = false,
	}
end

function PetInstance.levelCap(inst): number
	return Constants.EVOLUTION_LEVEL_CAP[inst.evolution] or 100
end

function PetInstance.xpToNext(level: number): number
	return Formulas.xpForLevel(level)
end

-- Adds XP, levelling up as far as the evolution cap allows. Returns levels gained.
function PetInstance.addXp(inst, amount: number): number
	local gained = 0
	local cap = PetInstance.levelCap(inst)
	inst.xp += math.max(0, math.floor(amount))
	while inst.level < cap and inst.xp >= PetInstance.xpToNext(inst.level) do
		inst.xp -= PetInstance.xpToNext(inst.level)
		inst.level += 1
		gained += 1
	end
	if inst.level >= cap then
		inst.xp = math.min(inst.xp, PetInstance.xpToNext(inst.level) - 1)
	end
	return gained
end

-- Coins to buy one level directly (idle coins -> power).
function PetInstance.levelUpCost(inst): number
	local rarityMult = Rarities.StatMult[Pets[inst.petId].rarity]
	return math.floor(20 * inst.level ^ 1.6 * rarityMult ^ 0.5) -- 25 -> 20 (2026-09-26 economy pass)
end

function PetInstance.canLevelUp(inst): boolean
	return inst.level < PetInstance.levelCap(inst)
end

function PetInstance.evolveCost(inst)
	return { essence = 10 * inst.evolution ^ 2, coins = 500 * 4 ^ (inst.evolution - 1) }
end

function PetInstance.canEvolve(inst): (boolean, string?)
	if inst.evolution >= #Constants.EVOLUTION_MULT then
		return false, "max evolution"
	end
	if inst.level < PetInstance.levelCap(inst) then
		return false, "reach level " .. PetInstance.levelCap(inst)
	end
	return true, nil
end

function PetInstance.starUpCost(inst): number
	return 10 * 2 ^ (inst.stars - 1)
end

function PetInstance.canStarUp(inst): (boolean, string?)
	if inst.stars >= Constants.MAX_STARS then
		return false, "max stars"
	end
	return true, nil
end

function PetInstance.dismantleValue(inst)
	local def = Pets[inst.petId]
	return {
		shards = PetInstance.SHARDS_BY_RARITY[def.rarity],
		essence = def.rarity == "Common" and 1 or (def.rarity == "Uncommon" and 2 or 4),
		element = def.element,
	}
end

-- Fusion: FUSE_COUNT pets of the same species and variant -> one pet of the next variant,
-- keeping the best level/stars/evolution among the inputs.
function PetInstance.canFuse(list): (boolean, string?)
	if #list ~= PetInstance.FUSE_COUNT then
		return false, "need " .. PetInstance.FUSE_COUNT .. " pets"
	end
	local petId, variant = list[1].petId, list[1].variant
	if not PetInstance.NEXT_VARIANT[variant] then
		return false, "already max variant"
	end
	for _, inst in list do
		if inst.petId ~= petId or inst.variant ~= variant then
			return false, "pets must share species and variant"
		end
		if inst.locked then
			return false, "a pet is locked"
		end
	end
	return true, nil
end

function PetInstance.fuseResult(list, uid: string, now: number?)
	local best = PetInstance.new(list[1].petId, uid, now)
	best.variant = PetInstance.NEXT_VARIANT[list[1].variant]
	for _, inst in list do
		best.level = math.max(best.level, inst.level)
		best.stars = math.max(best.stars, inst.stars)
		best.evolution = math.max(best.evolution, inst.evolution)
	end
	return best
end

function PetInstance.stats(inst, globalMult: number?)
	return Formulas.finalStats(Pets[inst.petId], inst, globalMult)
end

function PetInstance.power(inst, globalMult: number?): number
	return Formulas.power(PetInstance.stats(inst, globalMult))
end

return PetInstance
