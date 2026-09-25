--!nonstrict
-- Roguelike expedition: thin Roblox wrapper around the pure shared Run state machine.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Run = require(Shared.Expedition.Run)
local Talents = require(Shared.Config.Talents)
local Stages = require(Shared.Config.Stages)
local Builder = require(Shared.Combat.Builder)

local Registry = require(script.Parent.Parent.Registry)
local Remotes = require(script.Parent.Parent.Network.Remotes)

local ExpeditionService = Registry.register("ExpeditionService", {})

ExpeditionService.UNLOCK_STAGE = { zone = 1, stage = 5 } -- unlocked after clearing 1-5
ExpeditionService.EXCLUSIVE_DROP = { petId = "Mistlantern", chance = 0.03 }

local seeder = Random.new()

local function data(player)
	return Registry.get("DataService").Get(player)
end

function ExpeditionService.IsUnlocked(player): boolean
	local d = data(player)
	local u = ExpeditionService.UNLOCK_STAGE
	return (d.stages[Stages.key(u.zone, u.stage)] or 0) > 0
end

-- Public view of the run: the run table plus the currently reachable nodes.
local function view(player)
	local d = data(player)
	local run = d.expedition.run
	if not run then
		return {
			run = nil,
			talents = d.expedition.talents,
			tickets = d.tickets,
			marks = d.marks,
			unlocked = ExpeditionService.IsUnlocked(player),
		}
	end
	return {
		run = run,
		available = Run.available(run),
		talents = d.expedition.talents,
		tickets = d.tickets,
		marks = d.marks,
		unlocked = true,
	}
end

local function battleFn(player, petInst)
	return function(run, node, bonuses)
		local spec = Run.enemySpec(run, node)
		local a = Builder.build(petInst, {
			side = "A",
			slot = 1,
			relics = run.relics,
			hpFraction = run.hpFraction,
			bonuses = bonuses,
			globalMult = Registry.get("PetService").GlobalMult(player),
			displayName = petInst.nickname,
		})
		local b = Builder.buildEnemy(
			spec.petId,
			spec.zone,
			spec.stage,
			{ side = "B", slot = 1, extraMult = spec.extraMult }
		)
		local BattleService = Registry.get("BattleService")
		local result, payload = BattleService.Run(
			{ a },
			{ b },
			{ mode = "Expedition", floor = run.floor, nodeKind = node.kind }
		)
		BattleService.RecordOutcome(player, result.winner == "A")
		payload.rewards = { gold = 0 }
		BattleService.Send(player, payload)
		return result
	end
end

local function finalize(player)
	local d = data(player)
	local run = d.expedition.run
	if not run then
		return nil
	end
	local payout = Run.payout(run)
	Registry.get("EconomyService")
		.AddMany(player, { marks = payout.marks, coins = payout.coins, gems = payout.gems }, false)
	for _, id in run.relics do
		d.expedition.relicCodex[id] = true
	end
	d.expedition.bestFloor = math.max(d.expedition.bestFloor, payout.floorsCleared)
	if run.status == "Won" then
		local chance = ExpeditionService.EXCLUSIVE_DROP.chance
			* (1 + run.effects.exclusiveDropBonus)
		if seeder:NextNumber() < chance then
			local inst = Registry.get("PetService")
				.Grant(player, ExpeditionService.EXCLUSIVE_DROP.petId, "Normal", false)
			payout.exclusiveDrop = inst.petId
			Registry.get("AnnouncementService")
				.Broadcast(player.DisplayName .. " found a Mistlantern deep in the expedition!", "Legendary")
		end
	end
	d.expedition.lastSummary = payout
	d.expedition.run = nil
	Registry.get("DataService")
		.ReplicateKeys(player, { "expedition", "marks", "coins", "gems", "pets", "codex", "stats" })
	return payout
end

function ExpeditionService.StartRun(player, uid: string): (boolean, string?, any?)
	local d = data(player)
	if not ExpeditionService.IsUnlocked(player) then
		return false, "Clear stage 1-5 to unlock expeditions"
	end
	if d.expedition.run then
		return false, "A run is already in progress"
	end
	local inst = d.pets[uid]
	if not inst then
		return false, "Unknown pet"
	end
	for buildingId, b in d.camp.buildings do
		if table.find(b.workers, uid) then
			return false, "That pet is working in the " .. buildingId
		end
	end
	if not Registry.get("EconomyService").Spend(player, "tickets", 1, false) then
		return false, "No expedition tickets (the Outpost makes them)"
	end
	d.expedition.run = Run.new(seeder:NextInteger(1, 2 ^ 31 - 1), uid, d.expedition.talents)
	d.expedition.runs += 1
	Registry.get("DataService").ReplicateKeys(player, { "expedition", "tickets" })
	return true, nil, view(player)
end

function ExpeditionService.Move(player, nodeId: number): (boolean, string?, any?)
	local d = data(player)
	local run = d.expedition.run
	if not run then
		return false, "No active run"
	end
	local inst = d.pets[run.petUid]
	if not inst then
		Run.abandon(run)
		finalize(player)
		return false, "Your expedition pet no longer exists"
	end
	local ok, err = Run.move(run, nodeId, battleFn(player, inst))
	if not ok then
		return false, err
	end
	Registry.get("QuestService").Add(player, "expeditionNodes", 1)
	if run.status ~= "Active" then
		finalize(player)
	else
		Registry.get("DataService").ReplicateKeys(player, { "expedition" })
	end
	return true, nil, view(player)
end

function ExpeditionService.Choose(player, idx: number): (boolean, string?, any?)
	local run = data(player).expedition.run
	if not run then
		return false, "No active run"
	end
	local ok, err = Run.choose(run, idx)
	if not ok then
		return false, err
	end
	if run.status ~= "Active" then
		finalize(player)
	else
		Registry.get("DataService").ReplicateKeys(player, { "expedition" })
	end
	return true, nil, view(player)
end

function ExpeditionService.Abandon(player): (boolean, string?, any?)
	local run = data(player).expedition.run
	if not run then
		return false, "No active run"
	end
	Run.abandon(run)
	finalize(player)
	return true, nil, view(player)
end

function ExpeditionService.BuyTalent(player, talentId: string): (boolean, string?, any?)
	local d = data(player)
	local ok, why = Talents.canBuy(talentId, d.expedition.talents, d.marks)
	if not ok then
		return false, why
	end
	Registry.get("EconomyService").Spend(player, "marks", Talents.ById[talentId].cost, false)
	d.expedition.talents[talentId] = true
	Registry.get("DataService").ReplicateKeys(player, { "expedition", "marks" })
	return true, nil, view(player)
end

function ExpeditionService.Start()
	Remotes.handle("GetExpedition", function(player)
		if not data(player) then
			return false, "Bad request"
		end
		return true, nil, view(player)
	end)
	Remotes.handle("ExpeditionStart", function(player, uid)
		if not data(player) or not Remotes.str(uid, 16) then
			return false, "Bad request"
		end
		return ExpeditionService.StartRun(player, uid)
	end)
	Remotes.handle("ExpeditionMove", function(player, nodeId)
		local id = Remotes.int(nodeId, 1, 100)
		if not data(player) or not id then
			return false, "Bad request"
		end
		return ExpeditionService.Move(player, id)
	end)
	Remotes.handle("ExpeditionChoose", function(player, idx)
		local i = Remotes.int(idx, -1, 10)
		if not data(player) or not i then
			return false, "Bad request"
		end
		return ExpeditionService.Choose(player, i)
	end)
	Remotes.handle("ExpeditionAbandon", function(player)
		if not data(player) then
			return false, "Bad request"
		end
		return ExpeditionService.Abandon(player)
	end)
	Remotes.handle("ExpeditionBuyTalent", function(player, talentId)
		if not data(player) or not Remotes.str(talentId, 4) then
			return false, "Bad request"
		end
		return ExpeditionService.BuyTalent(player, talentId)
	end)
end

return ExpeditionService
