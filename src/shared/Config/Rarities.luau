--!nonstrict
-- Rarity tiers, variant (mutation) tiers and hatch odds.
-- NOTE: any egg purchasable with Robux (or Robux-bought currency) MUST show these odds
-- numerically before purchase (Roblox Paid Random Items policy). Keep odds here as the
-- single source of truth so the UI and the server always agree.
local Rarities = {}

Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

Rarities.StatMult = {
	Common = 1.0,
	Uncommon = 1.5,
	Rare = 2.5,
	Epic = 4.5,
	Legendary = 8.0,
	Mythic = 15.0,
	Secret = 30.0,
}

-- Rarities that trigger a server-wide announcement when hatched.
Rarities.Announce = { Legendary = true, Mythic = true, Secret = true }

Rarities.Variants = { "Normal", "Golden", "Rainbow", "DarkMatter" }
Rarities.VariantMult = { Normal = 1.0, Golden = 1.5, Rainbow = 2.5, DarkMatter = 5.0 }
Rarities.VariantDisplay = {
	Normal = "",
	Golden = "Golden",
	Rainbow = "Rainbow",
	DarkMatter = "Dark Matter",
}

-- Odds are fractions that sum to exactly 1.0 per egg.
Rarities.EggOdds = {
	MeadowEgg = { -- Zone 1, bought with coins
		Common = 0.55,
		Uncommon = 0.28,
		Rare = 0.12,
		Epic = 0.04,
		Legendary = 0.009,
		Mythic = 0.00099,
		Secret = 0.00001,
	},
	ForestEgg = { -- Zone 2
		Common = 0.50,
		Uncommon = 0.30,
		Rare = 0.14,
		Epic = 0.05,
		Legendary = 0.009,
		Mythic = 0.00099,
		Secret = 0.00001,
	},
	VolcanoEgg = { -- Zone 3
		Common = 0.45,
		Uncommon = 0.32,
		Rare = 0.16,
		Epic = 0.06,
		Legendary = 0.009,
		Mythic = 0.00099,
		Secret = 0.00001,
	},
	PremiumEgg = { -- bought with gems
		Rare = 0.45,
		Epic = 0.35,
		Legendary = 0.15,
		Mythic = 0.0495,
		Secret = 0.0005,
	},
}

-- Sanity: verify each odds table sums to 1 (within float tolerance).
function Rarities.validateOdds(): (boolean, string?)
	for eggId, odds in Rarities.EggOdds do
		local sum = 0
		for _, p in odds do
			sum += p
		end
		if math.abs(sum - 1) > 1e-9 then
			return false, string.format("egg %s odds sum to %.6f, expected 1", eggId, sum)
		end
	end
	return true, nil
end

return Rarities
