--!nonstrict
-- Player profile schema (ProfileStore template). Add fields here; ProfileStore reconciles new keys.
-- Bump SCHEMA_VERSION and add a migration in DataService when a field's meaning changes.
local Constants = require("./Config/Constants")

local DataTemplate = {
	schemaVersion = 1,

	-- Currencies
	coins = 0,
	gems = 0,
	essence = 0, -- evolution material
	shards = 0, -- star-up material (from dismantling)
	marks = 0, -- expedition talent currency
	medals = 0, -- arena currency (post-MVP shop)
	tickets = 3, -- expedition entries
	luck = 0, -- luck boost per hatch from consumables (e.g. 0.5 = Rare+ odds x1.5); numeric, shown in odds
	luckCharges = 0, -- hatches remaining on the boost

	-- Pets: pets[uid] = PetInstance ; team[tostring(slot)] = uid  (string keys keep sparse slots DataStore-safe)
	pets = {},
	team = {},
	nextUid = 1,

	-- PvE: stages[zone.."-"..stage] = stars (0..3)
	stages = {},

	-- Idle camp: camp.buildings[id] = { level, workers = {uid,...} }, camp.lastCollect = unix
	camp = {
		buildings = {},
		lastCollect = 0,
		pending = { coins = 0, tickets = 0 }, -- accrued but uncollected (server truth)
	},

	-- Expedition
	expedition = {
		run = nil, -- current run state or nil
		talents = {}, -- talents[id] = true
		relicCodex = {}, -- relicCodex[id] = true
		bestFloor = 0,
		runs = 0,
	},

	-- Collection: codex[petId][variant] = true
	codex = {},

	quests = {
		date = "", -- Quests.dateKey() when progress was reset
		progress = {}, -- key -> count
		claimed = {}, -- questId -> true
		bonusClaimed = false,
	},

	arena = {
		rating = 1000,
		wins = 0,
		losses = 0,
		defenseTeam = {}, -- snapshot uids
		fightsToday = 0,
		date = "",
	},

	prestige = {
		count = 0,
		points = 0,
		coinsEarnedThisRun = 0,
	},

	stats = {
		battlesWon = 0,
		battlesLost = 0,
		hatches = 0,
		playtime = 0,
		firstJoin = 0,
		lastSeen = 0,
		loginStreak = 0,
		lastDailyClaim = "",
	},

	settings = {
		battleSpeed = 1, -- 1|2|3
		autoSkip = false,
		music = true,
		sfx = true,
	},

	passes = {}, -- pass name -> true (VIP, TripleHatch, LuckyCharm)
	purchases = {}, -- receipt PurchaseId -> true (ProcessReceipt idempotency)
	tutorialStep = 0,
}

-- Fields that are safe to send to the client verbatim.
DataTemplate.PUBLIC_KEYS = {
	"coins",
	"gems",
	"essence",
	"shards",
	"marks",
	"medals",
	"tickets",
	"luck",
	"luckCharges",
	"pets",
	"team",
	"stages",
	"camp",
	"expedition",
	"codex",
	"quests",
	"arena",
	"prestige",
	"stats",
	"settings",
	"passes",
	"tutorialStep",
}

DataTemplate.MAX_TEAM_SLOTS = Constants.MAX_TEAM_SLOTS

return DataTemplate
