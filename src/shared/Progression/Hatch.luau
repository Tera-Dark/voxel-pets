--!nonstrict
-- Hatching: odds (with luck), rolling, and the disclosure table shown before purchase.
-- Roblox Paid Random Items policy: for eggs bought with Robux-purchasable currency, every
-- possible outcome must be listed with numeric odds summing to 100%, and luck boosts must be
-- reflected numerically while active. Hatch.disclosure() is the single source for that UI.
local Rarities = require("../Config/Rarities")
local Eggs = require("../Config/Eggs")

local Hatch = {}

local ORDER = Rarities.Order

-- luck >= 0: multiplies Rare+ odds by (1 + luck); the extra mass is taken from the lowest tiers.
function Hatch.oddsWithLuck(baseOdds, luck: number)
	local odds = table.clone(baseOdds)
	if not luck or luck <= 0 then
		return odds
	end
	local extra = 0
	for _, r in ORDER do
		if odds[r] and r ~= "Common" and r ~= "Uncommon" then
			local boosted = odds[r] * (1 + luck)
			extra += boosted - odds[r]
			odds[r] = boosted
		end
	end
	for _, r in { "Common", "Uncommon" } do
		if extra <= 0 then
			break
		end
		if odds[r] then
			local take = math.min(odds[r], extra)
			odds[r] -= take
			extra -= take
		end
	end
	if extra > 0 then
		-- pathological luck: renormalize
		local sum = 0
		for _, p in odds do
			sum += p
		end
		for r, p in odds do
			odds[r] = p / sum
		end
	end
	return odds
end

-- Returns an ordered list { {rarity, petId, odds}, ... } summing to 1 (each species splits its
-- rarity's odds evenly), plus the per-rarity table. Used for the "Details" popup.
function Hatch.disclosure(eggId: string, luck: number?)
	local egg = Eggs[eggId]
	local odds = Hatch.oddsWithLuck(Rarities.EggOdds[eggId], luck or 0)
	local rows, byRarity, sum = {}, {}, 0
	for _, r in ORDER do
		local p = odds[r]
		local pool = egg.pool[r]
		if p and p > 0 and pool and #pool > 0 then
			byRarity[r] = p
			for _, petId in pool do
				table.insert(rows, { rarity = r, petId = petId, odds = p / #pool })
				sum += p / #pool
			end
		end
	end
	return rows, byRarity, sum
end

function Hatch.roll(rng, eggId: string, luck: number?)
	local egg = Eggs[eggId]
	local odds = Hatch.oddsWithLuck(Rarities.EggOdds[eggId], luck or 0)
	local roll = rng:next()
	local acc = 0
	local rarity = nil
	for _, r in ORDER do
		if odds[r] then
			acc += odds[r]
			if roll < acc then
				rarity = r
				break
			end
		end
	end
	rarity = rarity or ORDER[1]
	-- fall back to lower rarities if the pool is empty for this egg
	local idx = table.find(ORDER, rarity)
	while idx >= 1 do
		local pool = egg.pool[ORDER[idx]]
		if pool and #pool > 0 then
			return pool[rng:int(1, #pool)], ORDER[idx]
		end
		idx -= 1
	end
	-- or higher
	for _, r in ORDER do
		if egg.pool[r] and #egg.pool[r] > 0 then
			return egg.pool[r][1], r
		end
	end
	error("egg has no pool: " .. eggId)
end

return Hatch
