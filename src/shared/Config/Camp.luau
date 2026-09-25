--!nonstrict
-- Idle camp: idle pets work in buildings and produce resources while the player is away.
local Camp = {}

Camp.OFFLINE_CAP_HOURS = 8
Camp.VIP_OFFLINE_CAP_HOURS = 12
Camp.MAX_LEVEL = 50

Camp.Buildings = {
	Mine = {
		displayName = "Cube Mine",
		produces = "coins",
		affinity = { Fire = true, Neutral = true },
		baseSlots = 3,
		maxSlots = 10,
		ratePerPower = 0.05, -- coins per second per (power^0.6)
		upgradeBaseCost = 200,
		unlock = { type = "None" },
		order = 1,
	},
	Orchard = {
		displayName = "Exp Orchard",
		produces = "xp", -- xp goes to the assigned pets themselves
		affinity = { Grass = true, Water = true },
		baseSlots = 2,
		maxSlots = 8,
		ratePerPower = 0.03,
		upgradeBaseCost = 500,
		unlock = { type = "StagesCleared", count = 5 },
		order = 2,
	},
	Outpost = {
		displayName = "Expedition Outpost",
		produces = "tickets",
		affinity = { Dark = true, Light = true },
		baseSlots = 1,
		maxSlots = 4,
		ratePerPower = 0, -- tickets: flat, see TICKETS_PER_HOUR
		upgradeBaseCost = 800,
		unlock = { type = "ExpeditionUnlocked" },
		order = 3,
	},
}

Camp.TICKETS_PER_HOUR_PER_WORKER = 0.25
Camp.TICKET_CAP = 5

function Camp.slots(buildingId: string, level: number): number
	local b = Camp.Buildings[buildingId]
	return math.min(b.maxSlots, b.baseSlots + math.floor((level - 1) / 5))
end

function Camp.levelMult(level: number): number
	return 1.15 ^ (level - 1)
end

function Camp.upgradeCost(buildingId: string, level: number): number
	local b = Camp.Buildings[buildingId]
	return math.floor(b.upgradeBaseCost * 1.25 ^ (level - 1))
end

-- Per-second production of one worker pet.
-- petInfo: { power, element, variantMult }
function Camp.workerRate(buildingId: string, level: number, petInfo, globalMult: number?): number
	local b = Camp.Buildings[buildingId]
	if b.ratePerPower == 0 then
		return 0
	end
	local affinity = b.affinity[petInfo.element] and 1.25 or 1
	return petInfo.power ^ 0.6
		* b.ratePerPower
		* affinity
		* (petInfo.variantMult or 1)
		* Camp.levelMult(level)
		* (globalMult or 1)
end

function Camp.isUnlocked(buildingId: string, ctx): boolean
	local u = Camp.Buildings[buildingId].unlock
	if u.type == "None" then
		return true
	elseif u.type == "StagesCleared" then
		return (ctx.stagesCleared or 0) >= u.count
	elseif u.type == "ExpeditionUnlocked" then
		return ctx.expeditionUnlocked == true
	end
	return false
end

return Camp
