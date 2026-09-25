--!nonstrict
-- Prestige ("Rebirth"): reset zone progress, coins and camp levels for permanent multipliers.
local Stages = require("./Stages")

local Prestige = {}

Prestige.PRODUCTION_PER_POINT = 0.08
Prestige.PET_STATS_PER_POINT = 0.03
Prestige.REQUIRED_ZONE = 3 -- must clear this zone's boss

Prestige.Milestones = {
	{ count = 1, displayName = "Auto-hatch unlocked", unlock = "autoHatch" },
	{ count = 3, displayName = "Rainbow fusion unlocked", unlock = "rainbowFusion" },
	{
		count = 5,
		displayName = "Dark Matter fusion + Secret egg pool",
		unlock = "darkMatterFusion",
	},
}

function Prestige.canPrestige(stagesData): boolean
	return (stagesData[Stages.key(Prestige.REQUIRED_ZONE, Stages.STAGES_PER_ZONE)] or 0) > 0
end

-- furthestStageIndex: linear index across zones (zone-1)*10 + stage of the furthest cleared stage.
function Prestige.pointsFor(furthestStageIndex: number, coinsEarnedThisRun: number): number
	return math.floor(
		furthestStageIndex ^ 1.2 / 20 + math.sqrt(math.max(0, coinsEarnedThisRun) / 1e6)
	)
end

function Prestige.productionMult(points: number): number
	return 1 + Prestige.PRODUCTION_PER_POINT * points
end

function Prestige.petStatMult(points: number): number
	return 1 + Prestige.PET_STATS_PER_POINT * points
end

function Prestige.furthestIndex(stagesData): number
	local best = 0
	for key, stars in stagesData do
		if stars > 0 then
			local zone, stage = string.match(key, "^(%d+)%-(%d+)$")
			if zone then
				best =
					math.max(best, (tonumber(zone) - 1) * Stages.STAGES_PER_ZONE + tonumber(stage))
			end
		end
	end
	return best
end

return Prestige
