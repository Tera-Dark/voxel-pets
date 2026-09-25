--!nonstrict
-- Expedition meta-progression: permanent talents bought with Expedition Marks.
-- Three branches, linear prerequisites within a branch.
local Talents = {}

Talents.Nodes = {
	-- Explorer
	{
		id = "E1",
		branch = "Explorer",
		displayName = "Packed Bags",
		description = "Start each run with 1 relic.",
		cost = 30,
		effect = { startRelics = 1 },
	},
	{
		id = "E2",
		branch = "Explorer",
		displayName = "Bargain Hunter",
		description = "Shop prices -20%.",
		cost = 40,
		effect = { shopDiscount = 0.2 },
	},
	{
		id = "E3",
		branch = "Explorer",
		displayName = "Foresight",
		description = "See node types 1 step further.",
		cost = 40,
		effect = { previewSteps = 1 },
	},
	{
		id = "E4",
		branch = "Explorer",
		displayName = "Second Look",
		description = "1 relic reroll per floor.",
		cost = 60,
		effect = { rerollsPerFloor = 1 },
	},
	{
		id = "E5",
		branch = "Explorer",
		displayName = "Cartographer",
		description = "+1 treasure node per floor.",
		cost = 80,
		effect = { extraTreasure = 1 },
	},
	-- Survival
	{
		id = "S1",
		branch = "Survival",
		displayName = "Thick Cubes",
		description = "+10% max HP in expeditions.",
		cost = 30,
		effect = { hpMult = 1.10 },
	},
	{
		id = "S2",
		branch = "Survival",
		displayName = "Warm Fire",
		description = "Campfire heals +15% more.",
		cost = 40,
		effect = { campfireBonus = 0.15 },
	},
	{
		id = "S3",
		branch = "Survival",
		displayName = "Sharpened",
		description = "+10% ATK in expeditions.",
		cost = 50,
		effect = { atkMult = 1.10 },
	},
	{
		id = "S4",
		branch = "Survival",
		displayName = "Guarded Start",
		description = "Start each battle with a 15% shield.",
		cost = 60,
		effect = { startShieldPct = 0.15 },
	},
	{
		id = "S5",
		branch = "Survival",
		displayName = "Second Wind",
		description = "Once per run, survive a defeat with 30% HP (disabled in weekly challenge).",
		cost = 100,
		effect = { secondWind = true },
	},
	-- Abyss
	{
		id = "A1",
		branch = "Abyss",
		displayName = "Deeper Pockets",
		description = "Unlock tier-2 relics in the pool.",
		cost = 50,
		effect = { relicTier2 = true },
	},
	{
		id = "A2",
		branch = "Abyss",
		displayName = "Mark Hunter",
		description = "+20% Expedition Marks.",
		cost = 50,
		effect = { marksMult = 1.2 },
	},
	{
		id = "A3",
		branch = "Abyss",
		displayName = "Golden Odds",
		description = "Legendary relics appear more often.",
		cost = 70,
		effect = { legendaryWeightBonus = 10 },
	},
	{
		id = "A4",
		branch = "Abyss",
		displayName = "Abyss Gate",
		description = "Unlock Abyss Levels (post-MVP).",
		cost = 90,
		effect = { abyssUnlocked = true },
	},
	{
		id = "A5",
		branch = "Abyss",
		displayName = "Lantern Keeper",
		description = "+25% chance of expedition-exclusive drops.",
		cost = 120,
		effect = { exclusiveDropBonus = 0.25 },
	},
}

Talents.ById = {}
for i, node in Talents.Nodes do
	node.index = i
	Talents.ById[node.id] = node
end

function Talents.prerequisite(id: string): string?
	local node = Talents.ById[id]
	local n = tonumber(string.sub(id, 2))
	if n and n > 1 then
		return string.sub(id, 1, 1) .. (n - 1)
	end
	return nil, node
end

-- owned: { [id] = true }
function Talents.canBuy(id: string, owned, marks: number): (boolean, string?)
	local node = Talents.ById[id]
	if not node then
		return false, "unknown talent"
	end
	if owned[id] then
		return false, "already owned"
	end
	local pre = Talents.prerequisite(id)
	if pre and not owned[pre] then
		return false, "requires " .. pre
	end
	if marks < node.cost then
		return false, "not enough marks"
	end
	return true, nil
end

-- Fold all owned effects into one table.
function Talents.effects(owned)
	local e = {
		startRelics = 0,
		shopDiscount = 0,
		previewSteps = 0,
		rerollsPerFloor = 0,
		extraTreasure = 0,
		hpMult = 1,
		atkMult = 1,
		campfireBonus = 0,
		startShieldPct = 0,
		secondWind = false,
		relicTier2 = false,
		marksMult = 1,
		legendaryWeightBonus = 0,
		abyssUnlocked = false,
		exclusiveDropBonus = 0,
	}
	for id in owned do
		local node = Talents.ById[id]
		if node then
			for k, v in node.effect do
				if
					type(v) == "number" and (k == "hpMult" or k == "atkMult" or k == "marksMult")
				then
					e[k] *= v
				elseif type(v) == "number" then
					e[k] += v
				else
					e[k] = v
				end
			end
		end
	end
	return e
end

return Talents
