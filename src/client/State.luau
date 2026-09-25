--!nonstrict
-- Client profile cache. Server sends ProfileDelta with top-level keys; we replace those keys and
-- notify listeners. Screens read State.profile and subscribe to State.Changed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local PetInstance = require(Shared.Progression.PetInstance)
local Codex = require(Shared.Progression.Codex)
local Prestige = require(Shared.Config.Prestige)

local State = {}
State.profile = nil
State.loaded = false

local changed = Instance.new("BindableEvent")
State.Changed = changed.Event -- (keys: {string})

function State.apply(delta)
	if not State.profile then
		State.profile = {}
	end
	local keys = {}
	for k, v in delta do
		State.profile[k] = v
		table.insert(keys, k)
	end
	State.loaded = true
	changed:Fire(keys)
end

function State.onKeys(keys: { string }, fn)
	local set = {}
	for _, k in keys do
		set[k] = true
	end
	return State.Changed:Connect(function(changedKeys)
		for _, k in changedKeys do
			if set[k] then
				fn()
				return
			end
		end
	end)
end

-- ---------------------------------------------------------------- helpers
function State.globalMult(): number
	local p = State.profile
	if not p then
		return 1
	end
	return Codex.bonusMult(p.codex or {})
		* Prestige.petStatMult((p.prestige and p.prestige.points) or 0)
end

function State.teamPet()
	local p = State.profile
	if not p or not p.team then
		return nil
	end
	local uid = p.team["1"]
	return uid and p.pets[uid] or nil, uid
end

-- Sorted pet list: team first, then by power desc.
function State.petList()
	local p = State.profile
	local list = {}
	if not p then
		return list
	end
	local teamUid = p.team and p.team["1"]
	local mult = State.globalMult()
	for uid, inst in p.pets do
		table.insert(list, {
			uid = uid,
			inst = inst,
			power = PetInstance.power(inst, mult),
			def = Pets[inst.petId],
		})
	end
	table.sort(list, function(a, b)
		if (a.uid == teamUid) ~= (b.uid == teamUid) then
			return a.uid == teamUid
		end
		if a.power ~= b.power then
			return a.power > b.power
		end
		return a.uid < b.uid
	end)
	return list
end

function State.power(inst): number
	return PetInstance.power(inst, State.globalMult())
end

function State.petName(inst): string
	return inst.nickname or Pets[inst.petId].displayName
end

function State.isBusy(uid: string): string?
	local p = State.profile
	if p.team and p.team["1"] == uid then
		return "Active"
	end
	for id, b in p.camp.buildings do
		if table.find(b.workers, uid) then
			return id
		end
	end
	if p.expedition and p.expedition.run and p.expedition.run.petUid == uid then
		return "Expedition"
	end
	return nil
end

return State
