--!nonstrict
-- Runs the deterministic simulator on the server and ships the event log to the client for playback.
-- Rewards are applied immediately (the outcome is final the moment the server simulates it).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Simulator = require(Shared.Combat.Simulator)

local Registry = require(script.Parent.Parent.Registry)
local Remotes = require(script.Parent.Parent.Network.Remotes)

local BattleService = Registry.register("BattleService", {})

local seeder = Random.new()

local function snapshot(c)
	return {
		uid = c.uid,
		side = c.side,
		slot = c.slot,
		petId = c.petId,
		name = c.name,
		element = c.element,
		level = c.level,
		maxHp = c.maxHp,
		hp = c.hp,
		atk = c.atk,
		def = c.def,
		spd = c.spd,
		power = c.power,
		rarity = c.rarity,
		variant = c.variant,
		relics = c.relics,
		skill = c.skills[1] and c.skills[1].id or nil,
	}
end

-- teamA/teamB: combatants from Builder.build. ctx: { mode = "Stage"|"Expedition"|"Arena", ... }
-- Returns the sim result plus a client payload; caller applies rewards and fires it.
function BattleService.Run(teamA, teamB, ctx)
	local seed = seeder:NextInteger(1, 2 ^ 31 - 1)
	local result = Simulator.run({ seed = seed, teamA = teamA, teamB = teamB, recordEvents = true })
	local payload = {
		seed = seed,
		mode = ctx.mode,
		context = ctx,
		teamA = {},
		teamB = {},
		winner = result.winner,
		duration = result.duration,
		timedOut = result.timedOut,
		hpLeft = result.hpLeft,
		events = result.events,
		rewards = nil, -- filled by the caller
	}
	for i, c in teamA do
		payload.teamA[i] = snapshot(c)
	end
	for i, c in teamB do
		payload.teamB[i] = snapshot(c)
	end
	return result, payload
end

function BattleService.Send(player, payload)
	Remotes.fire("BattleResult", player, payload)
end

function BattleService.RecordOutcome(player, won: boolean)
	local d = Registry.get("DataService").Get(player)
	if won then
		d.stats.battlesWon += 1
		Registry.get("QuestService").Add(player, "battlesWon", 1)
	else
		d.stats.battlesLost += 1
	end
end

return BattleService
