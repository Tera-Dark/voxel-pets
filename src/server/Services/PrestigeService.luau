--!nonstrict
-- Prestige: reset zone progress, coins and camp levels for permanent production / stat multipliers.
-- Kept: pets (levels/stars/evolutions), gems, essence/shards/marks, talents, codex, passes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Prestige = require(Shared.Config.Prestige)

local Registry = require(script.Parent.Parent.Registry)
local Remotes = require(script.Parent.Parent.Network.Remotes)

local PrestigeService = Registry.register("PrestigeService", {})

local function data(player)
	return Registry.get("DataService").Get(player)
end

function PrestigeService.ProductionMult(player): number
	local d = data(player)
	local mult = Prestige.productionMult(d.prestige.points)
	if Registry.get("MonetizationService").HasPass(player, "VIP") then
		mult *= 1.10
	end
	return mult
end

function PrestigeService.Preview(player)
	local d = data(player)
	local points =
		Prestige.pointsFor(Prestige.furthestIndex(d.stages), d.prestige.coinsEarnedThisRun)
	return {
		canPrestige = Prestige.canPrestige(d.stages),
		points = points,
		count = d.prestige.count,
		currentPoints = d.prestige.points,
		productionMult = Prestige.productionMult(d.prestige.points + points),
		petStatMult = Prestige.petStatMult(d.prestige.points + points),
		milestones = Prestige.Milestones,
	}
end

function PrestigeService.Do(player): (boolean, string?, any?)
	local d = data(player)
	if not Prestige.canPrestige(d.stages) then
		return false, "Defeat the " .. Prestige.REQUIRED_ZONE .. "rd zone boss first"
	end
	if d.expedition.run then
		return false, "Finish or abandon your expedition first"
	end
	local points = math.max(
		1,
		Prestige.pointsFor(Prestige.furthestIndex(d.stages), d.prestige.coinsEarnedThisRun)
	)
	Registry.get("CampService").Settle(player)
	d.prestige.count += 1
	d.prestige.points += points
	d.prestige.coinsEarnedThisRun = 0
	d.stages = {}
	d.coins = 0
	d.camp.pending.coins = 0
	for _, b in d.camp.buildings do
		b.level = 1
	end
	Registry.get("DataService").Replicate(player)
	Registry.get("AnnouncementService")
		.Broadcast(string.format("%s reached Prestige %d!", player.DisplayName, d.prestige.count), "Prestige")
	return true, nil, { points = points, total = d.prestige.points, count = d.prestige.count }
end

function PrestigeService.Start()
	Remotes.handle("Prestige", function(player)
		if not data(player) then
			return false, "Bad request"
		end
		return PrestigeService.Do(player)
	end)
	Remotes.handle("GetPrestige", function(player)
		if not data(player) then
			return false, "Bad request"
		end
		return true, nil, PrestigeService.Preview(player)
	end)
end

return PrestigeService
