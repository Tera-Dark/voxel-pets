--!nonstrict
-- New-player tutorial (shared/Config/Tutorial). The server owns progress: step 1 is recorded
-- when the player confirms a starter (ChooseStarter), later steps are derived from profile state
-- in Check(), which other services call after the actions that can complete a step. The
-- completion reward is paid once; skipping (TutorialSkip) finishes without the reward.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tutorial = require(Shared.Config.Tutorial)
local Codex = require(Shared.Progression.Codex)

local Registry = require(script.Parent.Parent.Registry)
local Remotes = require(script.Parent.Parent.Network.Remotes)

local TutorialService = Registry.register("TutorialService", {})

local function data(player)
	return Registry.get("DataService").Get(player)
end

-- Re-evaluates tutorial progress; pays the completion reward the first time it completes.
function TutorialService.Check(player)
	local d = data(player)
	if not d then
		return
	end
	local before = d.tutorialStep or 0
	local after = Tutorial.progress(d)
	if after == before then
		return
	end
	d.tutorialStep = after
	local keys = { "tutorialStep" }
	if after == Tutorial.COUNT and not d.tutorialRewarded then
		d.tutorialRewarded = true
		for currency, amount in Tutorial.REWARD do
			Registry.get("EconomyService").Add(player, currency, amount, false)
			table.insert(keys, currency)
		end
	end
	Registry.get("DataService").ReplicateKeys(player, keys)
end

-- Brand-new account still holding only its untouched auto-granted starter?
local function canSwapStarter(d): boolean
	local uid = d.team and d.team["1"]
	local inst = uid and d.pets[uid]
	local count = 0
	for _ in d.pets do
		count += 1
	end
	return inst ~= nil
		and count == 1
		and inst.level == 1
		and (inst.xp or 0) == 0
		and inst.evolution == 1
		and (d.stats.battlesWon + d.stats.battlesLost) == 0
end

function TutorialService.ChooseStarter(player, petId: string): (boolean, string?)
	local d = data(player)
	local starters = Registry.get("PetService").STARTERS
	if not table.find(starters, petId) then
		return false, "Bad request"
	end
	if (d.tutorialStep or 0) >= 1 then
		return false, "Partner already chosen"
	end
	if canSwapStarter(d) then
		local inst = d.pets[d.team["1"]]
		if inst.petId ~= petId then
			d.codex[inst.petId] = nil
			inst.petId = petId
			Codex.register(d.codex, petId, inst.variant)
		end
	end
	d.tutorialStep = 1
	Registry.get("DataService").ReplicateKeys(player, { "pets", "codex", "tutorialStep" })
	TutorialService.Check(player)
	return true
end

function TutorialService.Skip(player): (boolean, string?)
	local d = data(player)
	if (d.tutorialStep or 0) < Tutorial.COUNT then
		d.tutorialStep = Tutorial.SKIPPED
		Registry.get("DataService").ReplicateKeys(player, { "tutorialStep" })
	end
	return true
end

function TutorialService.Start()
	local DataService = Registry.get("DataService")
	-- catch up on load (e.g. progress made before the step logic existed)
	DataService.OnLoad("TutorialService.catchUp", function(_, d)
		d.tutorialStep = Tutorial.progress(d)
	end)
	Remotes.handle("ChooseStarter", function(player, petId)
		if not data(player) or not Remotes.str(petId, 32) then
			return false, "Bad request"
		end
		return TutorialService.ChooseStarter(player, petId)
	end)
	Remotes.handle("TutorialSkip", function(player)
		if not data(player) then
			return false, "Bad request"
		end
		return TutorialService.Skip(player)
	end)
end

return TutorialService
