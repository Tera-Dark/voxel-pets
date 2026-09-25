--!nonstrict
-- Expedition events: short text + 2 choices. Effects are declarative; ExpeditionService applies them.
--   hpPct        change current HP by a fraction of max HP (negative = cost)
--   gold         change run gold
--   relic        { rarity = "Rare"|"Legendary" } grant a random relic of that rarity
--   aura         { atkMult = 1.1 } or { hpMult = 1.1 } run-long buff
--   bossDamage   +% damage vs the floor boss
--   fuseCommons  fuse 2 common relics into 1 rare (requires >= 2 commons)
--   heal         alias for positive hpPct
local Events = {
	{
		id = "CubeAltar",
		title = "Cube Altar",
		text = "A humming altar of black cubes. It wants blood... or at least HP.",
		choices = {
			{
				text = "Sacrifice 25% max HP for a Legendary relic",
				effect = { hpPct = -0.25, relic = { rarity = "Legendary" } },
			},
			{ text = "Leave", effect = {} },
		},
	},
	{
		id = "LostPet",
		title = "Lost Pet",
		text = "A tiny wild pet follows you, hoping for a friend.",
		choices = {
			{
				text = "Let it tag along (+10% ATK this run)",
				effect = { aura = { atkMult = 1.1 } },
			},
			{ text = "Shoo it away (+30 gold)", effect = { gold = 30 } },
		},
	},
	{
		id = "MysteriousMerchant",
		title = "Mysterious Merchant",
		text = '"No gold? I accept other currencies." He eyes your health bar.',
		choices = {
			{
				text = "Pay 20% max HP for a Rare relic",
				effect = { hpPct = -0.2, relic = { rarity = "Rare" } },
			},
			{ text = "Leave", effect = {} },
		},
	},
	{
		id = "RiftEcho",
		title = "Rift Echo",
		text = "A crack in the air shows a glimpse of the floor boss.",
		choices = {
			{
				text = "Study it (+15% damage vs this floor's boss)",
				effect = { bossDamage = 0.15 },
			},
			{ text = "Loot the rift (+40 gold)", effect = { gold = 40 } },
		},
	},
	{
		id = "PixelFurnace",
		title = "Pixel Furnace",
		text = "A furnace that melts relics together.",
		choices = {
			{
				text = "Fuse 2 Common relics into 1 Rare",
				effect = { fuseCommons = true },
				requires = { commons = 2 },
			},
			{ text = "Leave", effect = {} },
		},
	},
	{
		id = "WanderingHealer",
		title = "Wandering Healer",
		text = "A kind old turtle offers a warm bandage.",
		choices = {
			{ text = "Rest (+30% HP)", effect = { hpPct = 0.3 } },
			{ text = "Take a tip instead (+25 gold)", effect = { gold = 25 } },
		},
	},
}

local Exports = { List = Events, ById = {} }
for _, e in Events do
	Exports.ById[e.id] = e
end

function Exports.pick(rng, exclude)
	exclude = exclude or {}
	local candidates = {}
	for _, e in Events do
		if not exclude[e.id] then
			table.insert(candidates, e)
		end
	end
	if #candidates == 0 then
		candidates = Events
	end
	return candidates[rng:int(1, #candidates)]
end

return Exports
