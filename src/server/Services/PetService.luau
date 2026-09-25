--!nonstrict
-- Owned pets: granting, team slots, level/evolve/star/dismantle/fuse, and building combatants.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Constants = require(Shared.Config.Constants)
local Prestige = require(Shared.Config.Prestige)
local PetInstance = require(Shared.Progression.PetInstance)
local Codex = require(Shared.Progression.Codex)
local Builder = require(Shared.Combat.Builder)

local Registry = require(script.Parent.Parent.Registry)
local Remotes = require(script.Parent.Parent.Network.Remotes)

local PetService = Registry.register("PetService", {})

PetService.MAX_PETS = 200
PetService.STARTERS = { "Emberfox", "Tidefrog", "Mossback" }

local function data(player)
	return Registry.get("DataService").Get(player)
end

local function replicate(player, keys)
	Registry.get("DataService").ReplicateKeys(player, keys)
end

-- ---------------------------------------------------------------- queries
function PetService.Count(player): number
	local n = 0
	for _ in data(player).pets do
		n += 1
	end
	return n
end

-- Account-wide stat multiplier: codex + prestige.
function PetService.GlobalMult(player): number
	local d = data(player)
	return Codex.bonusMult(d.codex) * Prestige.petStatMult(d.prestige.points)
end

function PetService.Get(player, uid: string)
	local d = data(player)
	return d and d.pets[uid] or nil
end

function PetService.ActiveTeam(player)
	local d = data(player)
	local list = {}
	for slot = 1, Constants.ACTIVE_TEAM_SLOTS do
		local uid = d.team[tostring(slot)] -- team keys are strings (DataStore-safe sparse slots)
		if uid and d.pets[uid] then
			table.insert(list, d.pets[uid])
		end
	end
	return list
end

function PetService.IsBusy(player, uid: string): (boolean, string?)
	local d = data(player)
	for slot, teamUid in d.team do
		if teamUid == uid then
			return true, "in team slot " .. slot
		end
	end
	for buildingId, b in d.camp.buildings do
		if table.find(b.workers, uid) then
			return true, "working in " .. buildingId
		end
	end
	if d.expedition.run and d.expedition.run.petUid == uid then
		return true, "on an expedition"
	end
	return false, nil
end

-- Builds team A combatants for a battle. opts: { relics, hpFraction, extraMult }
function PetService.BuildTeam(player, opts)
	opts = opts or {}
	local team = {}
	for slot, inst in PetService.ActiveTeam(player) do
		team[slot] = Builder.build(inst, {
			side = "A",
			slot = slot,
			relics = opts.relics,
			hpFraction = opts.hpFraction,
			globalMult = PetService.GlobalMult(player) * (opts.globalMult or 1),
			displayName = inst.nickname,
		})
	end
	return team
end

-- ---------------------------------------------------------------- mutations
function PetService.Grant(player, petId: string, variant: string?, replicateNow: boolean?)
	local d = data(player)
	assert(Pets[petId], "unknown pet " .. tostring(petId))
	local uid = "p" .. d.nextUid
	d.nextUid += 1
	local inst = PetInstance.new(petId, uid, os.time())
	inst.variant = variant or "Normal"
	d.pets[uid] = inst
	Codex.register(d.codex, petId, inst.variant)
	if replicateNow ~= false then
		replicate(player, { "pets", "nextUid", "codex" })
	end
	return inst
end

function PetService.AddXp(player, uid: string, amount: number): number
	local inst = PetService.Get(player, uid)
	if not inst then
		return 0
	end
	local gained = PetInstance.addXp(inst, amount)
	if gained > 0 then
		Registry.get("QuestService").Add(player, "levelUps", gained)
	end
	return gained
end

function PetService.SetTeam(player, slot: number, uid: string?): (boolean, string?)
	local d = data(player)
	if slot > Constants.ACTIVE_TEAM_SLOTS then
		return false, "Slot locked"
	end
	local key = tostring(slot)
	if uid == nil then
		if slot == 1 then
			return false, "Slot 1 must have a pet"
		end
		d.team[key] = nil
	else
		if not d.pets[uid] then
			return false, "Unknown pet"
		end
		if d.expedition.run then
			return false, "Finish or abandon your expedition first"
		end
		for _, b in d.camp.buildings do
			local idx = table.find(b.workers, uid)
			if idx then
				Registry.get("CampService").Settle(player) -- bank production before the roster changes
				table.remove(b.workers, idx) -- pull it out of the camp automatically
			end
		end
		for s, other in d.team do
			if other == uid and s ~= key then
				d.team[s] = d.team[key]
			end
		end
		d.team[key] = uid
	end
	replicate(player, { "team", "camp" })
	return true, nil
end

function PetService.LevelUp(player, uid: string, times: number): (boolean, string?)
	local inst = PetService.Get(player, uid)
	if not inst then
		return false, "Unknown pet"
	end
	local economy = Registry.get("EconomyService")
	local done = 0
	for _ = 1, times do
		if not PetInstance.canLevelUp(inst) then
			break
		end
		local cost = PetInstance.levelUpCost(inst)
		if not economy.Spend(player, "coins", cost, false) then
			break
		end
		inst.level += 1
		inst.xp = 0
		done += 1
	end
	if done == 0 then
		return false,
			PetInstance.canLevelUp(inst) and "Not enough coins" or "Max level for this evolution"
	end
	Registry.get("QuestService").Add(player, "levelUps", done)
	replicate(player, { "pets", "coins" })
	return true, nil
end

function PetService.Evolve(player, uid: string): (boolean, string?)
	local inst = PetService.Get(player, uid)
	if not inst then
		return false, "Unknown pet"
	end
	local ok, why = PetInstance.canEvolve(inst)
	if not ok then
		return false, why
	end
	if not Registry.get("EconomyService").SpendMany(player, PetInstance.evolveCost(inst)) then
		return false, "Not enough essence/coins"
	end
	inst.evolution += 1
	replicate(player, { "pets" })
	return true, nil
end

function PetService.StarUp(player, uid: string): (boolean, string?)
	local inst = PetService.Get(player, uid)
	if not inst then
		return false, "Unknown pet"
	end
	local ok, why = PetInstance.canStarUp(inst)
	if not ok then
		return false, why
	end
	if not Registry.get("EconomyService").Spend(player, "shards", PetInstance.starUpCost(inst)) then
		return false, "Not enough shards"
	end
	inst.stars += 1
	replicate(player, { "pets" })
	return true, nil
end

function PetService.Dismantle(player, uids: { string }): (boolean, string?, any?)
	local d = data(player)
	local total = { shards = 0, essence = 0 }
	for _, uid in uids do
		local inst = d.pets[uid]
		if not inst then
			return false, "Unknown pet"
		end
		if inst.locked then
			return false, "A selected pet is locked"
		end
		local busy, why = PetService.IsBusy(player, uid)
		if busy then
			return false, "Pet is " .. why
		end
	end
	if PetService.Count(player) - #uids < 1 then
		return false, "Keep at least one pet"
	end
	for _, uid in uids do
		local value = PetInstance.dismantleValue(d.pets[uid])
		total.shards += value.shards
		total.essence += value.essence
		d.pets[uid] = nil
	end
	Registry.get("EconomyService").AddMany(player, total, false)
	replicate(player, { "pets", "shards", "essence" })
	return true, nil, total
end

function PetService.Fuse(player, uids: { string }): (boolean, string?, string?)
	local d = data(player)
	local list = {}
	local seen = {}
	for _, uid in uids do
		if seen[uid] then
			return false, "Duplicate pet"
		end
		seen[uid] = true
		local inst = d.pets[uid]
		if not inst then
			return false, "Unknown pet"
		end
		local busy, why = PetService.IsBusy(player, uid)
		if busy then
			return false, "Pet is " .. why
		end
		table.insert(list, inst)
	end
	local ok, why = PetInstance.canFuse(list)
	if not ok then
		return false, why
	end
	local target = PetInstance.NEXT_VARIANT[list[1].variant]
	if target == "Rainbow" and d.prestige.count < 3 then
		return false, "Rainbow fusion unlocks at Prestige 3"
	elseif target == "DarkMatter" and d.prestige.count < 5 then
		return false, "Dark Matter fusion unlocks at Prestige 5"
	end
	local uid = "p" .. d.nextUid
	d.nextUid += 1
	local fused = PetInstance.fuseResult(list, uid, os.time())
	for _, inst in list do
		d.pets[inst.uid] = nil
	end
	d.pets[uid] = fused
	Codex.register(d.codex, fused.petId, fused.variant)
	replicate(player, { "pets", "nextUid", "codex" })
	return true, nil, uid
end

function PetService.SetLock(player, uid: string, locked: boolean): (boolean, string?)
	local inst = PetService.Get(player, uid)
	if not inst then
		return false, "Unknown pet"
	end
	inst.locked = locked
	replicate(player, { "pets" })
	return true, nil
end

function PetService.Rename(player, uid: string, name: string): (boolean, string?)
	local inst = PetService.Get(player, uid)
	if not inst then
		return false, "Unknown pet"
	end
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(name, player.UserId)
			:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return false, "Could not filter name"
	end
	inst.nickname = result
	replicate(player, { "pets" })
	return true, nil
end

-- ---------------------------------------------------------------- lifecycle
function PetService.Start()
	local DataService = Registry.get("DataService")
	DataService.PlayerLoaded:Connect(function(player, d)
		if next(d.pets) == nil then
			-- New account: give a random starter and put it in slot 1.
			local starter = PetService.STARTERS[math.random(1, #PetService.STARTERS)]
			local inst = PetService.Grant(player, starter, "Normal", false)
			d.team["1"] = inst.uid
		elseif not d.team["1"] or not d.pets[d.team["1"]] then
			d.team["1"] = next(d.pets)
		end
	end)

	Remotes.handle("SetTeam", function(player, slot, uid)
		local s = Remotes.int(slot, 1, Constants.MAX_TEAM_SLOTS)
		if not s or not data(player) then
			return false, "Bad request"
		end
		if uid ~= nil and not Remotes.str(uid, 16) then
			return false, "Bad request"
		end
		return PetService.SetTeam(player, s, uid)
	end)
	Remotes.handle("LevelUpPet", function(player, uid, times)
		local n = Remotes.int(times, 1, 100)
		if not data(player) or not Remotes.str(uid, 16) or not n then
			return false, "Bad request"
		end
		return PetService.LevelUp(player, uid, n)
	end)
	Remotes.handle("EvolvePet", function(player, uid)
		if not data(player) or not Remotes.str(uid, 16) then
			return false, "Bad request"
		end
		return PetService.Evolve(player, uid)
	end)
	Remotes.handle("StarUpPet", function(player, uid)
		if not data(player) or not Remotes.str(uid, 16) then
			return false, "Bad request"
		end
		return PetService.StarUp(player, uid)
	end)
	Remotes.handle("DismantlePets", function(player, uids)
		local list = Remotes.strList(uids, 50)
		if not data(player) or not list then
			return false, "Bad request"
		end
		return PetService.Dismantle(player, list)
	end)
	Remotes.handle("FusePets", function(player, uids)
		local list = Remotes.strList(uids, PetInstance.FUSE_COUNT)
		if not data(player) or not list then
			return false, "Bad request"
		end
		return PetService.Fuse(player, list)
	end)
	Remotes.handle("SetPetLock", function(player, uid, locked)
		if not data(player) or not Remotes.str(uid, 16) or type(locked) ~= "boolean" then
			return false, "Bad request"
		end
		return PetService.SetLock(player, uid, locked)
	end)
	Remotes.handle("RenamePet", function(player, uid, name)
		if not data(player) or not Remotes.str(uid, 16) or not Remotes.str(name, 16) then
			return false, "Bad request"
		end
		return PetService.Rename(player, uid, name)
	end)
end

return PetService
