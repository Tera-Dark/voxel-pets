--!nonstrict
-- Weighted relic offers for expedition choices.
local Relics = require("../Config/Relics")

local RelicPool = {}

local function byRarity()
	local groups = {}
	local ids = {}
	for id, def in Relics do
		if type(def) == "table" and def.rarity then
			table.insert(ids, id)
		end
	end
	table.sort(ids) -- deterministic iteration order regardless of table hashing
	for _, id in ids do
		local r = Relics[id].rarity
		groups[r] = groups[r] or {}
		table.insert(groups[r], id)
	end
	return groups
end

local GROUPS = byRarity()

-- opts: { count = 3, owned = {id=true}, legendaryWeightBonus = 0, allowCursed = true, minRarity = nil }
function RelicPool.offer(rng, opts)
	opts = opts or {}
	local count = opts.count or 3
	local owned = opts.owned or {}
	local weights = table.clone(Relics.Weights)
	weights.Legendary += opts.legendaryWeightBonus or 0
	if opts.allowCursed == false then
		weights.Cursed = 0
	end
	if opts.minRarity == "Rare" then
		weights.Common = 0
	elseif opts.minRarity == "Legendary" then
		weights.Common, weights.Rare, weights.Cursed = 0, 0, 0
	end

	local offered = {}
	local taken = {}
	for _ = 1, count do
		-- pick rarity, then a relic not owned / not already offered; fall back across rarities
		local total = 0
		for _, w in weights do
			total += w
		end
		local picked
		for attempt = 1, 12 do
			local roll = rng:next() * total
			local rarity = "Common"
			for r, w in weights do
				roll -= w
				if roll <= 0 then
					rarity = r
					break
				end
			end
			local group = GROUPS[rarity] or {}
			local candidates = {}
			for _, id in group do
				if not owned[id] and not taken[id] then
					table.insert(candidates, id)
				end
			end
			if #candidates > 0 then
				picked = candidates[rng:int(1, #candidates)]
				break
			end
			if attempt == 12 then
				break
			end
		end
		if not picked then
			-- everything of every rarity owned? offer anything not taken
			for _, group in GROUPS do
				for _, id in group do
					if not taken[id] then
						picked = id
						break
					end
				end
				if picked then
					break
				end
			end
		end
		if picked then
			taken[picked] = true
			table.insert(offered, picked)
		end
	end
	return offered
end

function RelicPool.price(relicId: string, discount: number?): number
	local r = Relics[relicId].rarity
	local base = r == "Legendary" and 150 or (r == "Rare" and 80 or (r == "Cursed" and 20 or 40))
	return math.floor(base * (1 - (discount or 0)))
end

return RelicPool
