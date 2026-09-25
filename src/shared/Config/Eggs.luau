--!nonstrict
-- Eggs: price, currency and species pool per rarity. Odds live in Rarities.EggOdds.
local Eggs = {
	MeadowEgg = {
		displayName = "Meadow Egg",
		zone = 1,
		price = { currency = "coins", amount = 100 },
		pool = {
			Common = {
				"GrassSlime",
				"Hopcube",
				"EmberBeetle",
				"PuddleSnail",
				"Pebblepup",
				"SporeToad",
			},
			Uncommon = { "Sunfinch", "Duskling" },
			Rare = { "Emberfox", "Tidefrog", "Mossback", "Aqualope", "Lumiwisp" },
			Epic = { "Dawnstag", "Shadeclaw", "Frostfin" },
			Legendary = { "Magmahorn" },
			Mythic = { "Prismwyrm" },
			Secret = { "VoidcubeDragon" },
		},
	},
	ForestEgg = {
		displayName = "Forest Egg",
		zone = 2,
		price = { currency = "coins", amount = 2500 },
		pool = {
			Common = { "ThornvineWolf", "Gloomcap", "BrambleBeetle", "Nightmoth" },
			Uncommon = { "Duskling", "Sunfinch" },
			Rare = { "Mossback", "Lumiwisp", "Aqualope" },
			Epic = { "Shadeclaw", "Dawnstag" },
			Legendary = { "Magmahorn" },
			Mythic = { "Prismwyrm" },
			Secret = { "VoidcubeDragon" },
		},
	},
	VolcanoEgg = {
		displayName = "Volcano Egg",
		zone = 3,
		price = { currency = "coins", amount = 60000 },
		pool = {
			Common = { "CinderPup", "SlagTortoise", "Ashwing", "MagmaSlug" },
			Uncommon = { "Sunfinch", "Duskling" },
			Rare = { "Emberfox", "Aqualope" },
			Epic = { "Frostfin", "Shadeclaw" },
			Legendary = { "Magmahorn" },
			Mythic = { "Prismwyrm" },
			Secret = { "VoidcubeDragon" },
		},
	},
	PremiumEgg = {
		displayName = "Premium Egg",
		zone = nil,
		price = { currency = "gems", amount = 250 },
		paidRandomItem = true, -- gems are purchasable with Robux -> odds disclosure + PolicyService gate
		pool = {
			Rare = { "Emberfox", "Tidefrog", "Mossback", "Aqualope", "Lumiwisp" },
			Epic = { "Dawnstag", "Shadeclaw", "Frostfin" },
			Legendary = { "Magmahorn", "Mistlantern" },
			Mythic = { "Prismwyrm" },
			Secret = { "VoidcubeDragon" },
		},
	},
}

for id, def in Eggs do
	def.id = id
end

return Eggs
