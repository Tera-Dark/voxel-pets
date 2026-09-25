--!nonstrict
-- Pet definitions. Base stats are level-1, Common-equivalent values; rarity/variant/level/star/
-- evolution multipliers are applied by Formulas.finalStats. SPD and CRIT do not scale with rarity.
-- passive: id handled by Combat/Builder (P0 hardcodes a small set; generalize later).
local Role = {
	-- Tuned with tools/tune_roles.luau (2026-09-25): neutral-element matchups
	-- Attacker-vs-Tank 50%, Attacker-vs-Support 55%, Tank-vs-Support 44%.
	Attacker = { hp = 320, atk = 20, def = 8, spd = 110, crit = 0.15 },
	Tank = { hp = 440, atk = 16, def = 12, spd = 90, crit = 0.08 },
	Support = { hp = 380, atk = 18, def = 11, spd = 100, crit = 0.08 },
	Control = { hp = 340, atk = 18, def = 9, spd = 105, crit = 0.10 },
}

local function pet(def)
	local base = Role[def.role]
	def.baseStats = def.baseStats or {}
	for k, v in base do
		if def.baseStats[k] == nil then
			def.baseStats[k] = v
		end
	end
	return def
end

local Pets = {
	-- ===== Starters (all Rare so the choice is about element/role, not power) =====
	Emberfox = pet({
		displayName = "Emberfox",
		element = "Fire",
		role = "Attacker",
		rarity = "Rare",
		skill = "BlazingDash",
		passive = "Kindled", -- +15% crit chance vs Burning targets
		starter = true,
		voxelHeight = 32,
	}),
	Tidefrog = pet({
		displayName = "Tidefrog",
		element = "Water",
		role = "Tank",
		rarity = "Rare",
		skill = "BubbleShield",
		passive = "SlickSkin", -- 10% chance to Chill attackers when hit
		starter = true,
		voxelHeight = 32,
	}),
	Mossback = pet({
		displayName = "Mossback",
		element = "Grass",
		role = "Support",
		rarity = "Rare",
		skill = "LifeSpores",
		passive = "RootedCalm", -- +15% DEF (becomes a team aura with multi-slot teams)
		starter = true,
		voxelHeight = 32,
	}),

	-- ===== Hatchable roster (P0 subset) =====
	Dawnstag = pet({
		displayName = "Dawnstag",
		element = "Light",
		role = "Support",
		rarity = "Epic",
		skill = "RadiantCleanse",
		passive = "SecondDawn", -- revive once at 30% HP
	}),
	Shadeclaw = pet({
		displayName = "Shadeclaw",
		element = "Dark",
		role = "Attacker",
		rarity = "Epic",
		skill = "ShadowStrike",
		passive = "Executioner", -- +50% damage vs targets below 30% HP
		baseStats = { spd = 120 },
	}),
	Magmahorn = pet({
		displayName = "Magmahorn",
		element = "Fire",
		role = "Tank",
		rarity = "Legendary",
		skill = "QuakeStomp",
		passive = "Hardening", -- +8% DEF per 10% HP lost
	}),
	Mistlantern = pet({
		displayName = "Mistlantern",
		element = "Dark",
		role = "Control",
		rarity = "Legendary",
		skill = "AbyssLure",
		passive = "DeepShield", -- expedition: start each floor with a shield (P0: start battle with 10% shield)
		expeditionOnly = true,
	}),

	-- ===== Zone 1 wild pets / enemies =====
	GrassSlime = pet({
		displayName = "Grass Slime",
		element = "Grass",
		role = "Tank",
		rarity = "Common",
		wild = true,
	}),
	Hopcube = pet({
		displayName = "Hopcube",
		element = "Neutral",
		role = "Attacker",
		rarity = "Common",
		wild = true,
	}),
	EmberBeetle = pet({
		displayName = "Ember Beetle",
		element = "Fire",
		role = "Attacker",
		rarity = "Common",
		wild = true,
	}),
	PuddleSnail = pet({
		displayName = "Puddle Snail",
		element = "Water",
		role = "Support",
		rarity = "Common",
		wild = true,
	}),
	ThornbackBoar = pet({
		displayName = "Thornback Boar",
		element = "Grass",
		role = "Attacker",
		rarity = "Common",
		skill = "WildCharge",
		wild = true,
		elite = true,
		baseStats = { hp = 360 },
	}),
	SporeToad = pet({
		displayName = "Spore Toad",
		element = "Grass",
		role = "Control",
		rarity = "Common",
		skill = "AcidSpit",
		wild = true,
	}),
	OakheartGolem = pet({
		displayName = "Oakheart Golem",
		element = "Grass",
		role = "Tank",
		rarity = "Common",
		skill = "BossQuake",
		passive = "Hardening",
		wild = true,
		boss = true,
		baseStats = { hp = 440 },
	}),

	-- ===== Zone 2: Mosslight Forest (Grass / Dark) =====
	ThornvineWolf = pet({
		displayName = "Thornvine Wolf",
		element = "Grass",
		role = "Attacker",
		rarity = "Common",
		skill = "AcidSpit",
		wild = true,
	}),
	Gloomcap = pet({
		displayName = "Gloomcap",
		element = "Dark",
		role = "Support",
		rarity = "Common",
		skill = "SporeCloud",
		wild = true,
	}),
	BrambleBeetle = pet({
		displayName = "Bramble Beetle",
		element = "Grass",
		role = "Tank",
		rarity = "Common",
		skill = "StoneWall",
		wild = true,
	}),
	Nightmoth = pet({
		displayName = "Nightmoth",
		element = "Dark",
		role = "Control",
		rarity = "Common",
		skill = "AbyssLure",
		wild = true,
	}),
	ShadowStag = pet({
		displayName = "Shadow Stag",
		element = "Dark",
		role = "Attacker",
		rarity = "Common",
		skill = "VoidRend",
		wild = true,
		elite = true,
		baseStats = { hp = 360 },
	}),
	RotwoodColossus = pet({
		displayName = "Rotwood Colossus",
		element = "Dark",
		role = "Tank",
		rarity = "Common",
		skill = "BossQuake",
		passive = "Hardening",
		wild = true,
		boss = true,
		baseStats = { hp = 440 },
	}),

	-- ===== Zone 3: Ember Volcano (Fire) =====
	CinderPup = pet({
		displayName = "Cinder Pup",
		element = "Fire",
		role = "Attacker",
		rarity = "Common",
		skill = "EmberBreath",
		wild = true,
	}),
	SlagTortoise = pet({
		displayName = "Slag Tortoise",
		element = "Fire",
		role = "Tank",
		rarity = "Common",
		skill = "StoneWall",
		wild = true,
	}),
	Ashwing = pet({
		displayName = "Ashwing",
		element = "Fire",
		role = "Control",
		rarity = "Common",
		skill = "EmberBreath",
		wild = true,
	}),
	MagmaSlug = pet({
		displayName = "Magma Slug",
		element = "Fire",
		role = "Support",
		rarity = "Common",
		skill = "LifeSpores",
		wild = true,
	}),
	BlazeBoar = pet({
		displayName = "Blaze Boar",
		element = "Fire",
		role = "Attacker",
		rarity = "Common",
		skill = "WildCharge",
		wild = true,
		elite = true,
		baseStats = { hp = 360 },
	}),
	FurnaceTitan = pet({
		displayName = "Furnace Titan",
		element = "Fire",
		role = "Tank",
		rarity = "Common",
		skill = "BossQuake",
		passive = "Hardening",
		wild = true,
		boss = true,
		baseStats = { hp = 460 },
	}),

	-- ===== Hatchable roster (MVP) =====
	Pebblepup = pet({
		displayName = "Pebblepup",
		element = "Neutral",
		role = "Tank",
		rarity = "Common",
		skill = "StoneWall",
	}),
	Sunfinch = pet({
		displayName = "Sunfinch",
		element = "Light",
		role = "Attacker",
		rarity = "Uncommon",
		skill = "SunFlare",
	}),
	Duskling = pet({
		displayName = "Duskling",
		element = "Dark",
		role = "Attacker",
		rarity = "Uncommon",
		skill = "VoidRend",
	}),
	Aqualope = pet({
		displayName = "Aqualope",
		element = "Water",
		role = "Attacker",
		rarity = "Rare",
		skill = "TidalSlam",
		passive = "SlickSkin",
	}),
	Lumiwisp = pet({
		displayName = "Lumiwisp",
		element = "Light",
		role = "Support",
		rarity = "Rare",
		skill = "RadiantCleanse",
	}),
	Frostfin = pet({
		displayName = "Frostfin",
		element = "Water",
		role = "Control",
		rarity = "Epic",
		skill = "TidalSlam",
		passive = "SlickSkin",
		baseStats = { spd = 112 },
	}),
	Prismwyrm = pet({
		displayName = "Prismwyrm",
		element = "Light",
		role = "Attacker",
		rarity = "Mythic",
		skill = "SunFlare",
		passive = "Executioner",
	}),
	VoidcubeDragon = pet({
		displayName = "Voidcube Dragon",
		element = "Neutral",
		role = "Attacker",
		rarity = "Secret",
		skill = "VoidRend",
		passive = "VoidScales", -- +20% all stats, immune to Root/Blind
		baseStats = { hp = 400, def = 12 },
	}),
}

for id, def in Pets do
	def.id = id
end

return Pets
