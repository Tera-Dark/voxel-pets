--!nonstrict
-- PvE stages: validates unlocks, simulates, applies rewards/stars, tracks first clears.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local Builder = require(Shared.Combat.Builder)

local Registry = require(script.Parent.Parent.Registry)
local Remotes = require(script.Parent.Parent.Network.Remotes)

local StageService = Registry.register("StageService", {})

local function data(player)
	return Registry.get("DataService").Get(player)
end

function StageService.ClearedCount(player): number
	local n = 0
	for _, stars in data(player).stages do
		if stars > 0 then
			n += 1
		end
	end
	return n
end

function StageService.Start_(player, zone: number, stage: number): (boolean, string?, any?)
	local d = data(player)
	if not Stages.isStageUnlocked(zone, stage, d.stages) then
		return false, "Stage locked"
	end
	local PetService = Registry.get("PetService")
	local teamA = PetService.BuildTeam(player)
	if #teamA == 0 then
		return false, "No pet in your team"
	end
	local enemyId = Stages.enemyFor(zone, stage)
	local teamB = { Builder.buildEnemy(enemyId, zone, stage, { side = "B", slot = 1 }) }

	local result, payload = Registry.get("BattleService")
		.Run(teamA, teamB, { mode = "Stage", zone = zone, stage = stage })
	local won = result.winner == "A"
	Registry.get("BattleService").RecordOutcome(player, won)

	local rewards = { coins = 0, xp = 0, gems = 0, essence = 0, stars = 0, firstClear = false }
	if won then
		local r = Stages.rewards(zone, stage)
		local key = Stages.key(zone, stage)
		local prevStars = d.stages[key] or 0
		local stars = Stages.starsFor(result, result.hpLeft.A)
		local prodMult = Registry.get("PrestigeService").ProductionMult(player)
		rewards.coins = math.floor(r.coins * prodMult)
		rewards.xp = r.xp
		rewards.essence = r.essence
		rewards.stars = stars
		if prevStars == 0 then
			rewards.firstClear = true
			rewards.gems = r.firstClearGems
		end
		d.stages[key] = math.max(prevStars, stars)
		Registry.get("EconomyService")
			.AddMany(
				player,
				{ coins = rewards.coins, gems = rewards.gems, essence = rewards.essence },
				false
			)
		for _, inst in PetService.ActiveTeam(player) do
			PetService.AddXp(player, inst.uid, rewards.xp)
		end
		-- codex: seeing a wild species counts as "encountered" only; catching is via eggs
	else
		-- consolation: 20% coins, 30% xp so losses still progress the idle loop
		local r = Stages.rewards(zone, stage)
		rewards.coins = math.floor(r.coins * 0.2)
		rewards.xp = math.floor(r.xp * 0.3)
		Registry.get("EconomyService").Add(player, "coins", rewards.coins, false)
		for _, inst in PetService.ActiveTeam(player) do
			PetService.AddXp(player, inst.uid, rewards.xp)
		end
	end
	payload.rewards = rewards
	Registry.get("DataService")
		.ReplicateKeys(player, { "coins", "gems", "essence", "stages", "pets", "stats" })
	Registry.get("BattleService").Send(player, payload)
	return true, nil, { winner = result.winner, rewards = rewards }
end

function StageService.Start()
	Remotes.handle("StartStage", function(player, zone, stage)
		local z = Remotes.int(zone, 1, #Stages.Zones)
		local s = Remotes.int(stage, 1, Stages.STAGES_PER_ZONE)
		if not data(player) or not z or not s then
			return false, "Bad request"
		end
		return StageService.Start_(player, z, s)
	end)
end

return StageService
