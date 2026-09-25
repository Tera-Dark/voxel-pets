--!nonstrict
-- PvE zones and stages (1v1). Stage 10 of each zone is the boss.
local Formulas = require("./Formulas")

local Stages = {}

Stages.Zones = {
	{
		id = 1,
		displayName = "Sprout Meadow",
		element = "Grass",
		egg = "MeadowEgg",
		pool = { "GrassSlime", "Hopcube", "EmberBeetle", "PuddleSnail", "SporeToad" },
		elite = "ThornbackBoar",
		boss = "OakheartGolem",
		unlock = { type = "None" },
	},
	{
		id = 2,
		displayName = "Mosslight Forest",
		element = "Dark",
		egg = "ForestEgg",
		pool = { "ThornvineWolf", "Gloomcap", "BrambleBeetle", "Nightmoth" },
		elite = "ShadowStag",
		boss = "RotwoodColossus",
		unlock = { type = "BossCleared", zone = 1 },
	},
	{
		id = 3,
		displayName = "Ember Volcano",
		element = "Fire",
		egg = "VolcanoEgg",
		pool = { "CinderPup", "SlagTortoise", "Ashwing", "MagmaSlug" },
		elite = "BlazeBoar",
		boss = "FurnaceTitan",
		unlock = { type = "BossCleared", zone = 2 },
	},
}

Stages.STAGES_PER_ZONE = 10
Stages.STAR_HP_THRESHOLD = 0.5 -- 2nd star: finish with >= 50% HP
Stages.STAR_TIME_LIMIT = 30 -- 3rd star: finish within 30 s

function Stages.key(zone: number, stage: number): string
	return zone .. "-" .. stage
end

function Stages.getZone(zone: number)
	return Stages.Zones[zone]
end

-- Deterministic enemy pick for a stage (same stage always shows the same enemy).
function Stages.enemyFor(zone: number, stage: number): (string, string)
	local z = Stages.Zones[zone]
	if stage == Stages.STAGES_PER_ZONE then
		return z.boss, "Boss"
	elseif stage % 5 == 0 then
		return z.elite, "Elite"
	end
	return z.pool[((stage - 1) % #z.pool) + 1], "Normal"
end

function Stages.rewards(zone: number, stage: number)
	local _, kind = Stages.enemyFor(zone, stage)
	local scale = 2.5 ^ (zone - 1) * 1.12 ^ (stage - 1)
	local coins = math.floor(20 * scale)
	local xp = math.floor(15 * 2 ^ (zone - 1) * 1.1 ^ (stage - 1))
	local firstClearGems = kind == "Boss" and 25 or (kind == "Elite" and 10 or 3)
	local essence = kind == "Boss" and 5 or 0
	if kind == "Elite" then
		coins = math.floor(coins * 1.5)
		xp = math.floor(xp * 1.5)
	elseif kind == "Boss" then
		coins = math.floor(coins * 3)
		xp = math.floor(xp * 3)
	end
	return {
		coins = coins,
		xp = xp,
		firstClearGems = firstClearGems,
		essence = essence,
		kind = kind,
	}
end

function Stages.enemyScale(zone: number, stage: number): number
	return Formulas.enemyScale(zone, stage)
end

-- stagesData: { [key] = stars }
function Stages.isZoneUnlocked(zone: number, stagesData): boolean
	local z = Stages.Zones[zone]
	if not z then
		return false
	end
	if z.unlock.type == "None" then
		return true
	elseif z.unlock.type == "BossCleared" then
		return (stagesData[Stages.key(z.unlock.zone, Stages.STAGES_PER_ZONE)] or 0) > 0
	end
	return false
end

function Stages.isStageUnlocked(zone: number, stage: number, stagesData): boolean
	if not Stages.isZoneUnlocked(zone, stagesData) then
		return false
	end
	if stage == 1 then
		return true
	end
	return (stagesData[Stages.key(zone, stage - 1)] or 0) > 0
end

function Stages.starsFor(result, hpLeftFraction: number): number
	if result.winner ~= "A" then
		return 0
	end
	local stars = 1
	if hpLeftFraction >= Stages.STAR_HP_THRESHOLD then
		stars += 1
	end
	if result.duration <= Stages.STAR_TIME_LIMIT then
		stars += 1
	end
	return stars
end

return Stages
