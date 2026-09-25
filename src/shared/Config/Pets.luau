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
		baseStats = { hp = 380 },
	}),
	SporeToad = pet({
		displayName = "Spore Toad",
		element = "Grass",
		role = "Control",
		rarity = "Common",
		skill = "AcidSpit",
		wild = true,
	}),
}

for id, def in Pets do
	def.id = id
end

return Pets
