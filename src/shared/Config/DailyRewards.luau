--!strict
-- 7-day login reward cycle (shared so the client can render the strip without a round-trip).
local DailyRewards = {
	{ coins = 200 },
	{ gems = 10 },
	{ coins = 500 },
	{ essence = 5 },
	{ gems = 20 },
	{ tickets = 2 },
	{ gems = 40, coins = 1000 },
}

return DailyRewards
