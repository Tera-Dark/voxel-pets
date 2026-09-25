--!nonstrict
-- Single source of truth for remote names. Server creates them under ReplicatedStorage.Remotes.
-- Convention: Functions are request/response (client -> server), Events are server -> client pushes
-- unless listed under ClientEvents.
local Network = {
	FOLDER = "Remotes",

	Functions = {
		-- Profile
		"GetProfile", -- () -> snapshot of the public profile
		-- Pets / team
		"SetTeam", -- (slot, uid|nil) -> ok, err
		"LevelUpPet", -- (uid, times) -> ok, err
		"EvolvePet", -- (uid) -> ok, err
		"StarUpPet", -- (uid) -> ok, err
		"DismantlePets", -- ({uid}) -> ok, err, rewards
		"FusePets", -- ({uid x5}) -> ok, err, newUid
		"SetPetLock", -- (uid, locked) -> ok
		"RenamePet", -- (uid, name) -> ok, err
		-- Hatch
		"GetHatchOdds", -- (eggId) -> rows, byRarity   (numeric disclosure incl. active luck)
		"HatchEgg", -- (eggId, count) -> ok, err, results
		-- Stages
		"StartStage", -- (zone, stage) -> ok, err, battlePayload
		-- Expedition
		"ExpeditionStart", -- (uid) -> ok, err, runState
		"ExpeditionMove", -- (nodeId) -> ok, err, runState|battlePayload
		"ExpeditionChoose", -- (choiceIndex) -> ok, err, runState  (relic pick / event choice / shop buy / skip)
		"ExpeditionAbandon", -- () -> ok
		"ExpeditionBuyTalent", -- (talentId) -> ok, err
		-- Camp
		"CampAssign", -- (buildingId, slot, uid|nil) -> ok, err
		"CampUpgrade", -- (buildingId) -> ok, err
		"CampCollect", -- () -> ok, err, rewards
		-- Arena
		"ArenaGetOpponents", -- () -> list of 3 { name, power, rating, team }
		"ArenaFight", -- (index) -> ok, err, battlePayload
		"ArenaLeaderboard", -- () -> top 50
		-- Quests / prestige / shop
		"ClaimQuest", -- (questId) -> ok, err
		"Prestige", -- () -> ok, err, points
		"GetShop", -- () -> product list with ids + prices
		"BuyWithGems", -- (itemId) -> ok, err
		"ClaimDaily", -- () -> ok, err, reward
		"SetSetting", -- (key, value) -> ok
		"TutorialStep", -- (step) -> ok
	},

	Events = {
		"ProfileDelta", -- (partialTable) merge into client cache
		"BattleResult", -- (payload) full event log for playback
		"Announcement", -- (text, kind) global rare-hatch ticker
		"Toast", -- (text, kind) short notification
		"OfflineReport", -- (report) shown once on join
	},
}

Network.RATE_LIMITS = { -- calls per 10 seconds per remote (server-side)
	default = 30,
	HatchEgg = 15,
	StartStage = 10,
	ArenaFight = 6,
	LevelUpPet = 60,
}

return Network
