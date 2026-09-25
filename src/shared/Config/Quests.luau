--!nonstrict
-- Daily quests. Progress keys are incremented by services via QuestService:Add(player, key, n).
local Quests = {}

Quests.Daily = {
	{
		id = "WinBattles",
		displayName = "Win 5 battles",
		key = "battlesWon",
		goal = 5,
		reward = { coins = 150 },
	},
	{
		id = "HatchEggs",
		displayName = "Hatch 3 eggs",
		key = "hatches",
		goal = 3,
		reward = { gems = 10 },
	},
	{
		id = "ExpeditionNodes",
		displayName = "Clear 8 expedition nodes",
		key = "expeditionNodes",
		goal = 8,
		reward = { gems = 15 },
	},
	{
		id = "CampCollect",
		displayName = "Collect camp production 2 times",
		key = "campCollects",
		goal = 2,
		reward = { coins = 150 },
	},
	{
		id = "LevelUps",
		displayName = "Level up pets 5 times",
		key = "levelUps",
		goal = 5,
		reward = { coins = 100 },
	},
	{
		id = "ArenaFights",
		displayName = "Fight 3 arena battles",
		key = "arenaFights",
		goal = 3,
		reward = { gems = 5 },
	},
}

Quests.AllCompleteBonus = { gems = 20 }

Quests.ById = {}
for _, q in Quests.Daily do
	Quests.ById[q.id] = q
end

-- UTC date string used as the daily reset key.
function Quests.dateKey(now: number?): string
	return os.date("!%Y-%m-%d", now or os.time())
end

return Quests
