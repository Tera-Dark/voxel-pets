--!nonstrict
-- Coarse pacing model: how long does a player need (active hours / idle hours) to afford the
-- level required by each zone boss, given stage rewards + camp income? Prints a table; use it
-- when touching COIN_BASE, levelUpCost, Camp rates or enemy scaling.
-- Usage: lune run tools/economy_model
local Stages = require("../src/shared/Config/Stages")
local Camp = require("../src/shared/Config/Camp")
local PetInstance = require("../src/shared/Progression/PetInstance")

local BATTLES_PER_HOUR = 120 -- ~30 s per stage incl. UI at 2x playback
local WORKERS = { 1, 2, 3 } -- mine workers available per zone (roster grows)
-- Levels the zone boss needs for a Rare starter (tools/pve_curve, "best" column, 2026-09-26)
local BOSS_LEVEL = { 17, 33, 61 }
local ZONE_ENTRY_LEVEL = { 1, 17, 33 }

local function coinsToReach(fromLevel, toLevel)
	local inst = PetInstance.new("Emberfox", "x", 0)
	local total = 0
	for level = fromLevel, toLevel - 1 do
		inst.level = level
		inst.evolution = level > 60 and 3 or (level > 30 and 2 or 1)
		total += PetInstance.levelUpCost(inst)
		if level == 30 or level == 60 then
			total += PetInstance.evolveCost(inst).coins
		end
	end
	return total
end

local function minePerHour(zone, workerLevel)
	local inst = PetInstance.new("Emberfox", "x", 0)
	inst.level = workerLevel
	inst.evolution = workerLevel > 30 and 2 or 1
	local rate = Camp.workerRate(
		"Mine",
		1 + (zone - 1) * 5,
		{ power = PetInstance.power(inst), element = "Fire" }
	)
	return rate * 3600 * WORKERS[zone]
end

print("zone  needCoins  battle/h  mine/h(workers)  activeHours  idleHours(8h cap = overnight)")
for zone = 1, 3 do
	local need = coinsToReach(ZONE_ENTRY_LEVEL[zone], BOSS_LEVEL[zone])
	local perBattle = 0
	for stage = 1, 9 do
		perBattle += Stages.rewards(zone, stage).coins
	end
	perBattle /= 9
	local battleIncome = perBattle * BATTLES_PER_HOUR
	local mine = minePerHour(zone, ZONE_ENTRY_LEVEL[zone] + 5)
	local active = need / (battleIncome + mine)
	local idle = need / mine
	print(
		string.format(
			"  %d   %9d  %8d  %9d (%d)      %5.1f        %5.1f",
			zone,
			need,
			battleIncome,
			mine,
			WORKERS[zone],
			active,
			idle
		)
	)
end
print(string.format("\nMeadow egg %d coins, Forest %d, Volcano %d", 500, 2500, 25000))
