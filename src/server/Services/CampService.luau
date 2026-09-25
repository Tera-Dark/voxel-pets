--!nonstrict
-- Idle camp: pets assigned to buildings produce coins / XP / tickets over time, including offline.
-- Production is settled lazily (on every read/mutation) from camp.lastCollect; pending amounts
-- accrue server-side and are paid out on CampCollect.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Camp = require(Shared.Config.Camp)
local Pets = require(Shared.Config.Pets)
local Rarities = require(Shared.Config.Rarities)
local PetInstance = require(Shared.Progression.PetInstance)

local Registry = require(script.Parent.Parent.Registry)
local Remotes = require(script.Parent.Parent.Network.Remotes)

local CampService = Registry.register("CampService", {})

local function data(player)
	return Registry.get("DataService").Get(player)
end

local function building(d, id)
	local b = d.camp.buildings[id]
	if not b then
		b = { level = 1, workers = {}, xpPending = {} }
		d.camp.buildings[id] = b
	end
	b.xpPending = b.xpPending or {}
	return b
end

local function unlockCtx(player)
	return {
		stagesCleared = Registry.get("StageService").ClearedCount(player),
		expeditionUnlocked = Registry.get("ExpeditionService").IsUnlocked(player),
	}
end

function CampService.OfflineCapSeconds(player): number
	local hours = Registry.get("MonetizationService").HasPass(player, "VIP")
			and Camp.VIP_OFFLINE_CAP_HOURS
		or Camp.OFFLINE_CAP_HOURS
	return hours * 3600
end

-- Per-second rates for the current assignment.
function CampService.Rates(player)
	local d = data(player)
	local globalMult = Registry.get("PrestigeService").ProductionMult(player)
	local petMult = Registry.get("PetService").GlobalMult(player)
	local rates = { coins = 0, tickets = 0, xp = {} }
	for id, def in Camp.Buildings do
		local b = d.camp.buildings[id]
		if b then
			for _, uid in b.workers do
				local inst = d.pets[uid]
				if inst then
					local petDef = Pets[inst.petId]
					local info = {
						power = PetInstance.power(inst, petMult),
						element = petDef.element,
						variantMult = Rarities.VariantMult[inst.variant],
					}
					if def.produces == "coins" then
						rates.coins += Camp.workerRate(id, b.level, info, globalMult)
					elseif def.produces == "xp" then
						rates.xp[uid] = Camp.workerRate(id, b.level, info, globalMult)
					elseif def.produces == "tickets" then
						rates.tickets += Camp.TICKETS_PER_HOUR_PER_WORKER / 3600 * Camp.levelMult(
							b.level
						)
					end
				end
			end
		end
	end
	return rates
end

-- Accrues production since lastCollect into pending buckets. Returns the seconds settled.
function CampService.Settle(player): number
	local d = data(player)
	local now = os.time()
	if d.camp.lastCollect == 0 then
		d.camp.lastCollect = now
		return 0
	end
	local elapsed = math.max(0, now - d.camp.lastCollect)
	d.camp.lastCollect = now
	if elapsed == 0 then
		return 0
	end
	local rates = CampService.Rates(player)
	d.camp.pending.coins += rates.coins * elapsed
	d.camp.pending.tickets += rates.tickets * elapsed
	for uid, rate in rates.xp do
		local orchard = d.camp.buildings.Orchard
		if orchard then
			orchard.xpPending[uid] = (orchard.xpPending[uid] or 0) + rate * elapsed
		end
	end
	return elapsed
end

function CampService.Assign(
	player,
	buildingId: string,
	slot: number,
	uid: string?
): (boolean, string?)
	local d = data(player)
	local def = Camp.Buildings[buildingId]
	if not def then
		return false, "Unknown building"
	end
	if not Camp.isUnlocked(buildingId, unlockCtx(player)) then
		return false, "Building locked"
	end
	CampService.Settle(player)
	local b = building(d, buildingId)
	if slot < 1 or slot > Camp.slots(buildingId, b.level) then
		return false, "Slot locked"
	end
	if uid == nil then
		table.remove(b.workers, slot)
	else
		if not d.pets[uid] then
			return false, "Unknown pet"
		end
		local busy, why = Registry.get("PetService").IsBusy(player, uid)
		if busy then
			return false, "Pet is " .. why
		end
		if #b.workers >= Camp.slots(buildingId, b.level) and not b.workers[slot] then
			return false, "No free slot"
		end
		if b.workers[slot] then
			b.workers[slot] = uid
		else
			table.insert(b.workers, uid)
		end
	end
	Registry.get("DataService").ReplicateKeys(player, { "camp" })
	return true, nil
end

function CampService.Upgrade(player, buildingId: string): (boolean, string?)
	local d = data(player)
	if not Camp.Buildings[buildingId] then
		return false, "Unknown building"
	end
	if not Camp.isUnlocked(buildingId, unlockCtx(player)) then
		return false, "Building locked"
	end
	CampService.Settle(player)
	local b = building(d, buildingId)
	if b.level >= Camp.MAX_LEVEL then
		return false, "Max level"
	end
	if
		not Registry.get("EconomyService")
			.Spend(player, "coins", Camp.upgradeCost(buildingId, b.level), false)
	then
		return false, "Not enough coins"
	end
	b.level += 1
	Registry.get("DataService").ReplicateKeys(player, { "camp", "coins" })
	return true, nil
end

function CampService.Collect(player): (boolean, string?, any?)
	local d = data(player)
	CampService.Settle(player)
	local coins = math.floor(d.camp.pending.coins)
	local tickets = math.floor(d.camp.pending.tickets)
	tickets = math.min(tickets, math.max(0, Camp.TICKET_CAP - d.tickets))
	local xpTotal, levelUps = 0, 0
	local orchard = d.camp.buildings.Orchard
	if orchard then
		for uid, xp in orchard.xpPending do
			local amount = math.floor(xp)
			if d.pets[uid] and amount > 0 then
				levelUps += Registry.get("PetService").AddXp(player, uid, amount)
				xpTotal += amount
			end
			orchard.xpPending[uid] = nil
		end
	end
	if coins == 0 and tickets == 0 and xpTotal == 0 then
		return false, "Nothing to collect yet"
	end
	d.camp.pending.coins -= coins
	d.camp.pending.tickets = math.max(0, d.camp.pending.tickets - tickets)
	Registry.get("EconomyService").AddMany(player, { coins = coins, tickets = tickets }, false)
	Registry.get("QuestService").Add(player, "campCollects", 1)
	Registry.get("DataService").ReplicateKeys(player, { "camp", "coins", "tickets", "pets" })
	return true, nil, { coins = coins, tickets = tickets, xp = xpTotal, levelUps = levelUps }
end

-- Called on join: settle capped offline time and tell the player what they earned.
function CampService.OnJoin(player)
	local d = data(player)
	local now = os.time()
	if d.camp.lastCollect > 0 then
		local away = now - d.camp.lastCollect
		local cap = CampService.OfflineCapSeconds(player)
		if away > cap then
			-- pretend the pets stopped working at the cap
			d.camp.lastCollect = now - cap
		end
		local before = { coins = d.camp.pending.coins, tickets = d.camp.pending.tickets }
		local settled = CampService.Settle(player)
		if settled > 60 then
			Remotes.fire("OfflineReport", player, {
				seconds = settled,
				capped = away > cap,
				coins = math.floor(d.camp.pending.coins - before.coins),
				tickets = math.floor(d.camp.pending.tickets - before.tickets),
			})
		end
	else
		d.camp.lastCollect = now
	end
end

-- Public snapshot for the client (rates + pending + slots + unlock state).
function CampService.Snapshot(player)
	local d = data(player)
	CampService.Settle(player)
	local rates = CampService.Rates(player)
	local out = {
		buildings = {},
		pending = d.camp.pending,
		ratesPerHour = { coins = rates.coins * 3600, tickets = rates.tickets * 3600 },
	}
	local ctx = unlockCtx(player)
	for id, def in Camp.Buildings do
		local b = d.camp.buildings[id]
		local level = b and b.level or 1
		out.buildings[id] = {
			level = level,
			slots = Camp.slots(id, level),
			workers = b and b.workers or {},
			unlocked = Camp.isUnlocked(id, ctx),
			upgradeCost = Camp.upgradeCost(id, level),
			produces = def.produces,
			displayName = def.displayName,
			order = def.order,
		}
	end
	return out
end

function CampService.Start()
	Registry.get("DataService").PlayerLoaded:Connect(function(player)
		task.defer(CampService.OnJoin, player)
	end)
	Registry.get("DataService").PlayerUnloading:Connect(function(player)
		CampService.Settle(player)
	end)
	-- periodic settle so pending values shown in UI stay fresh and offline math has recent anchors
	task.spawn(function()
		while true do
			task.wait(30)
			for _, player in game:GetService("Players"):GetPlayers() do
				if data(player) then
					pcall(CampService.Settle, player)
				end
			end
		end
	end)

	Remotes.handle("CampAssign", function(player, buildingId, slot, uid)
		local s = Remotes.int(slot, 1, 10)
		if
			not data(player)
			or not Remotes.str(buildingId, 16)
			or not s
			or (uid ~= nil and not Remotes.str(uid, 16))
		then
			return false, "Bad request"
		end
		return CampService.Assign(player, buildingId, s, uid)
	end)
	Remotes.handle("CampUpgrade", function(player, buildingId)
		if not data(player) or not Remotes.str(buildingId, 16) then
			return false, "Bad request"
		end
		return CampService.Upgrade(player, buildingId)
	end)
	Remotes.handle("CampCollect", function(player)
		if not data(player) then
			return false, "Bad request"
		end
		return CampService.Collect(player)
	end)
	Remotes.handle("GetCamp", function(player)
		if not data(player) then
			return false, "Bad request"
		end
		return true, nil, CampService.Snapshot(player)
	end)
end

return CampService
