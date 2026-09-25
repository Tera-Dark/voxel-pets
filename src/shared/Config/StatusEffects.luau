--!nonstrict
-- Eight launch status effects. Values are read by the simulator; UI reads display fields.
local StatusEffects = {
	Burn = {
		displayName = "Burn",
		kind = "debuff",
		stackable = true,
		maxStacks = 5,
		duration = 4,
		tickEvery = 1,
		damagePerStackPctOfSourceAtk = 0.10,
	},
	Chill = { displayName = "Chill", kind = "debuff", duration = 3, attackSpeedMult = 0.7 },
	Root = { displayName = "Root", kind = "debuff", duration = 1.5, blocksBasicAttacks = true },
	Blind = { displayName = "Blind", kind = "debuff", duration = 2, basicMissChance = 0.5 },
	Vulnerable = {
		displayName = "Vulnerable",
		kind = "debuff",
		duration = 4,
		damageTakenMult = 1.25,
	},
	Shield = { displayName = "Shield", kind = "buff", duration = 6 }, -- amount stored on the combatant
	Regen = {
		displayName = "Regen",
		kind = "buff",
		duration = 4,
		tickEvery = 1,
		healPctMaxHp = 0.02,
	},
	Haste = { displayName = "Haste", kind = "buff", duration = 8, attackSpeedMult = 1.3 },
}

return StatusEffects
