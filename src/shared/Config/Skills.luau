--!nonstrict
-- Active skills. Combat is fully automatic: each skill carries a *trigger* that the AI evaluates.
-- trigger kinds:
--   Ready                       cast as soon as cooldown is ready
--   SelfHpBelow  {value}        cast when own HP% < value
--   TargetHpBelow {value}       cast when target HP% < value
--   TargetHasStatus {status}    cast when target has the status
--   SelfHasDebuff               cast when carrying any debuff
-- Conditional triggers fall back to casting after `maxWait` seconds of being ready
-- (Constants.DEFAULT_TRIGGER_MAX_WAIT when nil) so a pet never sits on a ready skill forever.
-- castTime > 0 makes the skill a *charge* (visible bar) that can be interrupted.
-- effects (applied in order):
--   { type = "Damage", mult = n }
--   { type = "Status", status = id, target = "Enemy"|"Self", stacks = n? }
--   { type = "Heal", pctMaxHp = n }
--   { type = "Shield", pctMaxHp = n }
--   { type = "Cleanse" }  (remove all debuffs from self)
local Skills = {
	BlazingDash = {
		displayName = "Blazing Dash",
		description = "Dash through the target for 220% damage and apply 2 Burn.",
		cooldown = 8,
		trigger = { kind = "TargetHasStatus", status = "Burn", maxWait = 3 },
		effects = {
			{ type = "Damage", mult = 2.2 },
			{ type = "Status", status = "Burn", target = "Enemy", stacks = 2 },
		},
	},
	BubbleShield = {
		displayName = "Bubble Shield",
		description = "Gain a shield equal to 15% max HP.",
		cooldown = 10,
		trigger = { kind = "SelfHpBelow", value = 0.6, maxWait = 6 },
		effects = { { type = "Shield", pctMaxHp = 0.15 } },
	},
	LifeSpores = {
		displayName = "Life Spores",
		description = "Heal 10% max HP and gain Regen for 4s.",
		cooldown = 12,
		trigger = { kind = "SelfHpBelow", value = 0.5, maxWait = 8 },
		effects = {
			{ type = "Heal", pctMaxHp = 0.10 },
			{ type = "Status", status = "Regen", target = "Self" },
		},
	},
	RadiantCleanse = {
		displayName = "Radiant Cleanse",
		description = "Remove all debuffs and gain Haste for 8s.",
		cooldown = 12,
		trigger = { kind = "SelfHasDebuff", maxWait = 4 },
		effects = { { type = "Cleanse" }, { type = "Status", status = "Haste", target = "Self" } },
	},
	ShadowStrike = {
		displayName = "Shadow Strike",
		description = "Strike from the shadows for 350% damage.",
		cooldown = 9,
		trigger = { kind = "TargetHpBelow", value = 0.3, maxWait = 4 },
		effects = { { type = "Damage", mult = 3.5 } },
	},
	QuakeStomp = {
		displayName = "Quake Stomp",
		description = "Stomp for 180% damage and Root the target.",
		cooldown = 10,
		trigger = { kind = "Ready" },
		effects = {
			{ type = "Damage", mult = 1.8 },
			{ type = "Status", status = "Root", target = "Enemy" },
		},
	},
	AbyssLure = {
		displayName = "Abyss Lure",
		description = "Blind the target for 2s and deal 120% damage.",
		cooldown = 9,
		trigger = { kind = "Ready" },
		effects = {
			{ type = "Status", status = "Blind", target = "Enemy" },
			{ type = "Damage", mult = 1.2 },
		},
	},
	-- Roster skills (MVP)
	TidalSlam = {
		displayName = "Tidal Slam",
		description = "Slam for 200% damage and Chill the target.",
		cooldown = 9,
		trigger = { kind = "Ready" },
		effects = {
			{ type = "Damage", mult = 2.0 },
			{ type = "Status", status = "Chill", target = "Enemy" },
		},
	},
	EmberBreath = {
		displayName = "Ember Breath",
		description = "Breathe fire for 150% damage and apply 1 Burn.",
		cooldown = 7,
		trigger = { kind = "Ready" },
		effects = {
			{ type = "Damage", mult = 1.5 },
			{ type = "Status", status = "Burn", target = "Enemy", stacks = 1 },
		},
	},
	SunFlare = {
		displayName = "Sun Flare",
		description = "Flash for 180% damage and Blind the target.",
		cooldown = 9,
		trigger = { kind = "Ready" },
		effects = {
			{ type = "Damage", mult = 1.8 },
			{ type = "Status", status = "Blind", target = "Enemy" },
		},
	},
	VoidRend = {
		displayName = "Void Rend",
		description = "Tear for 260% damage. Prefers wounded targets.",
		cooldown = 9,
		trigger = { kind = "TargetHpBelow", value = 0.5, maxWait = 5 },
		effects = { { type = "Damage", mult = 2.6 } },
	},
	StoneWall = {
		displayName = "Stone Wall",
		description = "Gain a shield equal to 20% max HP.",
		cooldown = 11,
		trigger = { kind = "SelfHpBelow", value = 0.7, maxWait = 6 },
		effects = { { type = "Shield", pctMaxHp = 0.2 } },
	},
	SporeCloud = {
		displayName = "Spore Cloud",
		description = "Blind the target and gain Regen.",
		cooldown = 10,
		trigger = { kind = "Ready" },
		effects = {
			{ type = "Status", status = "Blind", target = "Enemy" },
			{ type = "Status", status = "Regen", target = "Self" },
		},
	},
	BossQuake = {
		displayName = "Boss Quake",
		description = "Charges for 1.5s, then quakes for 250% damage and Roots the target. Can be interrupted.",
		cooldown = 9,
		castTime = 1.5,
		trigger = { kind = "Ready" },
		effects = {
			{ type = "Damage", mult = 2.5 },
			{ type = "Status", status = "Root", target = "Enemy" },
		},
	},
	-- Enemy skills
	WildCharge = {
		displayName = "Wild Charge",
		description = "Charges for 2s, then slams for 300% damage. Can be interrupted.",
		cooldown = 8,
		castTime = 2,
		trigger = { kind = "Ready" },
		effects = { { type = "Damage", mult = 3.0 } },
	},
	AcidSpit = {
		displayName = "Acid Spit",
		description = "Deal 120% damage and apply Vulnerable.",
		cooldown = 7,
		trigger = { kind = "Ready" },
		effects = {
			{ type = "Damage", mult = 1.2 },
			{ type = "Status", status = "Vulnerable", target = "Enemy" },
		},
	},
}

return Skills
