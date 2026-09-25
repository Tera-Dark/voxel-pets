--!nonstrict
-- Daily quests: UTC reset, progress counters fed by other services, claim + all-complete bonus.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Quests = require(ReplicatedStorage.Shared.Config.Quests)

local Registry = require(script.Parent.Parent.Registry)
local Remotes = require(script.Parent.Parent.Network.Remotes)

local QuestService = Registry.register("QuestService", {})

local function data(player)
	return Registry.get("DataService").Get(player)
end

function QuestService.EnsureFresh(player)
	local d = data(player)
	local today = Quests.dateKey()
	if d.quests.date ~= today then
		d.quests.date = today
		d.quests.progress = {}
		d.quests.claimed = {}
		d.quests.bonusClaimed = false
		return true
	end
	return false
end

function QuestService.Add(player, key: string, n: number)
	local d = data(player)
	if not d then
		return
	end
	QuestService.EnsureFresh(player)
	d.quests.progress[key] = (d.quests.progress[key] or 0) + n
	Registry.get("DataService").ReplicateKeys(player, { "quests" })
end

function QuestService.Claim(player, questId: string): (boolean, string?, any?)
	local d = data(player)
	QuestService.EnsureFresh(player)
	local q = Quests.ById[questId]
	if not q then
		return false, "Unknown quest"
	end
	if d.quests.claimed[questId] then
		return false, "Already claimed"
	end
	if (d.quests.progress[q.key] or 0) < q.goal then
		return false, "Not complete yet"
	end
	d.quests.claimed[questId] = true
	local rewards = table.clone(q.reward)
	local all = true
	for _, other in Quests.Daily do
		if not d.quests.claimed[other.id] then
			all = false
			break
		end
	end
	if all and not d.quests.bonusClaimed then
		d.quests.bonusClaimed = true
		for currency, amount in Quests.AllCompleteBonus do
			rewards[currency] = (rewards[currency] or 0) + amount
		end
		rewards.bonus = true
	end
	Registry.get("EconomyService").AddMany(player, rewards, false)
	Registry.get("DataService").ReplicateKeys(player, { "quests", "coins", "gems" })
	return true, nil, rewards
end

function QuestService.Start()
	Registry.get("DataService").PlayerLoaded:Connect(function(player)
		QuestService.EnsureFresh(player)
	end)
	Remotes.handle("ClaimQuest", function(player, questId)
		if not data(player) or not Remotes.str(questId, 32) then
			return false, "Bad request"
		end
		return QuestService.Claim(player, questId)
	end)
end

return QuestService
