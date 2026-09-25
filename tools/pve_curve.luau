--!nonstrict
-- PvE difficulty curve: for every zone/stage, find the lowest starter level that wins >= 50%.
-- Reference progression: Lv 1-30 evo 1, Lv 31-60 evo 2, Lv 61+ evo 3; stars = zone number.
--   neutral = the 3 starters forced to Neutral element, averaged (pure stat/skill curve)
--   best    = best of the 3 real starters (player routes around the element triangle)
-- Usage: lune run tools/pve_curve -- [--n=40] [--zone=2]
local process = require("@lune/process")
local Stages = require("../src/shared/Config/Stages")
local Builder = require("../src/shared/Combat/Builder")
local Simulator = require("../src/shared/Combat/Simulator")

local N, onlyZone = 40, nil
for _, a in process.args do
	local n = string.match(a, "^%-%-n=(%d+)$")
	local z = string.match(a, "^%-%-zone=(%d+)$")
	if n then
		N = tonumber(n)
	elseif z then
		onlyZone = tonumber(z)
	end
end

local STARTERS = { "Emberfox", "Tidefrog", "Mossback" }

local function instanceFor(level, zone)
	local evo = level > 60 and 3 or (level > 30 and 2 or 1)
	return { level = level, evolution = evo, stars = zone }
end

local function winRate(zone, stage, level, mode)
	local enemyId = Stages.enemyFor(zone, stage)
	local best, sum = 0, 0
	for _, starter in STARTERS do
		local inst = instanceFor(level, zone)
		inst.petId = starter
		local wins = 0
		for seed = 1, N do
			local a = Builder.build(
				inst,
				{ side = "A", slot = 1, elementOverride = mode == "neutral" and "Neutral" or nil }
			)
			local b = Builder.buildEnemy(enemyId, zone, stage, { side = "B", slot = 1 })
			local r =
				Simulator.run({ seed = seed, teamA = { a }, teamB = { b }, recordEvents = false })
			if r.winner == "A" then
				wins += 1
			end
		end
		best = math.max(best, wins / N)
		sum += wins / N
	end
	return mode == "best" and best or sum / #STARTERS
end

local function minLevel(zone, stage, mode)
	local lo, hi = 1, 100
	if winRate(zone, stage, hi, mode) < 0.5 then
		return nil
	end
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if winRate(zone, stage, mid, mode) >= 0.5 then
			hi = mid
		else
			lo = mid + 1
		end
	end
	return lo
end

print(string.format("== PvE curve: min starter level for >= 50%% win (N=%d per starter)", N))
for _, z in Stages.Zones do
	if not onlyZone or onlyZone == z.id then
		print("zone " .. z.id .. " " .. z.displayName)
		local prevN, prevB = nil, nil
		for stage = 1, Stages.STAGES_PER_ZONE do
			local lvN = minLevel(z.id, stage, "neutral")
			local lvB = minLevel(z.id, stage, "best")
			local enemy, kind = Stages.enemyFor(z.id, stage)
			local jumpN = (prevN and lvN) and string.format("%+d", lvN - prevN) or ""
			local jumpB = (prevB and lvB) and string.format("%+d", lvB - prevB) or ""
			print(
				string.format(
					"  %d-%-2d %-16s %-6s neutral %-4s %-4s best %-4s %s",
					z.id,
					stage,
					enemy,
					kind,
					tostring(lvN),
					jumpN,
					tostring(lvB),
					jumpB
				)
			)
			prevN = lvN or prevN
			prevB = lvB or prevB
		end
	end
end
