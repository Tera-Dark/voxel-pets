--!nonstrict
-- Expedition (roguelike) relics: the player's only in-run lever. P0 ships 15.
-- Effects are declarative; Combat/Builder folds them into combatant modifiers.
--   statMult = { hp=, atk=, def=, spd=, crit= }      multiplicative (crit is additive)
--   cooldownMult                                      multiplies skill cooldowns
--   elementMode = "neutralize" | "invert"
--   canInterrupt = true                               enables the interrupt trigger
--   onSkillHit = { burnStacks=, lifestealPct= }
--   onBasicHit = { chillChance= }
--   healToShieldPct                                   part of heals also granted as shield
--   firstSkillFree = true                             first skill cast has no cooldown
--   startHpLossPct                                    HP lost at battle start (cursed)
--   runGoldMult                                       out-of-combat, handled by the expedition service
local Relics = {
	SturdyBlock = {
		displayName = "Sturdy Block",
		rarity = "Common",
		description = "+15% max HP.",
		statMult = { hp = 1.15 },
	},
	Whetstone = {
		displayName = "Whetstone",
		rarity = "Common",
		description = "+10% ATK.",
		statMult = { atk = 1.10 },
	},
	IronHide = {
		displayName = "Iron Hide",
		rarity = "Common",
		description = "+25% DEF.",
		statMult = { def = 1.25 },
	},
	QuickPaws = {
		displayName = "Quick Paws",
		rarity = "Common",
		description = "+10% attack speed.",
		statMult = { spd = 1.10 },
	},
	LuckyCube = {
		displayName = "Lucky Cube",
		rarity = "Common",
		description = "+8% crit chance.",
		statMult = { crit = 0.08 },
	},

	EmberHeart = {
		displayName = "Ember Heart",
		rarity = "Rare",
		description = "Skill hits apply +2 Burn.",
		onSkillHit = { burnStacks = 2 },
	},
	FrostCharm = {
		displayName = "Frost Charm",
		rarity = "Rare",
		description = "Basic attacks have a 20% chance to Chill.",
		onBasicHit = { chillChance = 0.2 },
	},
	VampiricFang = {
		displayName = "Vampiric Fang",
		rarity = "Rare",
		description = "Skill hits heal for 20% of damage dealt.",
		onSkillHit = { lifestealPct = 0.20 },
	},
	EchoWhistle = {
		displayName = "Echo Whistle",
		rarity = "Rare",
		description = "Skill cooldowns -20%.",
		cooldownMult = 0.8,
	},
	ElementWard = {
		displayName = "Element Ward",
		rarity = "Rare",
		description = "Element disadvantage penalties are halved.",
		elementMode = "neutralize",
	},
	InsightLens = {
		displayName = "Insight Lens",
		rarity = "Rare",
		description = "Your pet interrupts enemy charges with its skill for +50% damage.",
		canInterrupt = true,
	},

	TimeHourglass = {
		displayName = "Time Hourglass",
		rarity = "Legendary",
		description = "The first skill each battle has no cooldown.",
		firstSkillFree = true,
	},
	SymbioticVine = {
		displayName = "Symbiotic Vine",
		rarity = "Legendary",
		description = "50% of healing received is also gained as shield.",
		healToShieldPct = 0.5,
	},
	InversionPrism = {
		displayName = "Inversion Prism",
		rarity = "Legendary",
		description = "Element matchups are reversed.",
		elementMode = "invert",
	},

	GreedyBox = {
		displayName = "Greedy Box",
		rarity = "Cursed",
		description = "Double expedition gold, but lose 5% HP at the start of every battle.",
		runGoldMult = 2,
		startHpLossPct = 0.05,
	},
}

for id, def in Relics do
	def.id = id
end

Relics.Weights = { Common = 45, Rare = 35, Legendary = 15, Cursed = 5 }

return Relics
