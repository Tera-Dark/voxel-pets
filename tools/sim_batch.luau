--!nonstrict
-- Balance snapshot: runs many seeded battles and prints win rates / durations.
-- usage: lune run tools/sim_batch -- [--quick] [--n=1000]
local process = require("@lune/process")
local Builder = require("../src/shared/Combat/Builder")
local Simulator = require("../src/shared/Combat/Simulator")

local N = 1000
for _, a in process.args do
	if a == "--quick" then
		N = 300
	end
	local n = string.match(a, "^%-%-n=(%d+)$")
	if n then
		N = tonumber(n)
	end
end

local function matchup(buildA, buildB, n)
	local wins, draws, dur, timeouts = 0, 0, 0, 0
	for seed = 1, n do
		local r = Simulator.run({
			seed = seed * 7919,
			teamA = { buildA() },
			teamB = { buildB() },
			recordEvents = false,
		})
		if r.winner == "A" then
			wins += 1
		elseif r.winner == "Draw" then
			draws += 1
		end
		if r.timedOut then
			timeouts += 1
		end
		dur += r.duration
	end
	return wins / n * 100, dur / n, timeouts
end

local function pct(x)
	return string.format("%5.1f%%", x)
end
local function header(title)
	print("")
	print("== " .. title)
end

local clock = os.clock()
local STARTERS = { "Emberfox", "Tidefrog", "Mossback" }

header(string.format("Starter triangle, Lv10, no relics (row = A win%% vs column, N=%d)", N))
print(string.format("%-10s %10s %10s %10s   avg duration", "", table.unpack(STARTERS)))
for _, pa in STARTERS do
	local cells, durs = {}, {}
	for _, pb in STARTERS do
		local w, d = matchup(function()
			return Builder.build({ petId = pa, level = 10 }, { side = "A" })
		end, function()
			return Builder.build({ petId = pb, level = 10 }, { side = "B" })
		end, N)
		table.insert(cells, pct(w))
		table.insert(durs, string.format("%.0fs", d))
	end
	print(
		string.format(
			"%-10s %10s %10s %10s   %s",
			pa,
			cells[1],
			cells[2],
			cells[3],
			table.concat(durs, " / ")
		)
	)
end

header("Role balance, elements neutralized (all forced Neutral), Lv10")
print(string.format("%-10s %10s %10s %10s   avg duration", "", table.unpack(STARTERS)))
for _, pa in STARTERS do
	local cells, durs = {}, {}
	for _, pb in STARTERS do
		local w, d = matchup(function()
			return Builder.build(
				{ petId = pa, level = 10 },
				{ side = "A", elementOverride = "Neutral" }
			)
		end, function()
			return Builder.build(
				{ petId = pb, level = 10 },
				{ side = "B", elementOverride = "Neutral" }
			)
		end, N)
		table.insert(cells, pct(w))
		table.insert(durs, string.format("%.0fs", d))
	end
	print(
		string.format(
			"%-10s %10s %10s %10s   %s",
			pa .. "*",
			cells[1],
			cells[2],
			cells[3],
			table.concat(durs, " / ")
		)
	)
end

header("Zone 1 progression: starter at Lv=stage vs wild pool at that stage (win%, avg s)")
local POOL = { "GrassSlime", "Hopcube", "EmberBeetle", "PuddleSnail", "SporeToad" }
print(string.format("%-10s %s", "stage:", "   1        3        5        7        10"))
for _, pa in STARTERS do
	local cells = {}
	for _, stage in { 1, 3, 5, 7, 10 } do
		local wSum, dSum = 0, 0
		for _, enemy in POOL do
			local w, d = matchup(function()
				return Builder.build({ petId = pa, level = stage }, { side = "A" })
			end, function()
				return Builder.buildEnemy(enemy, 1, stage)
			end, math.max(50, N // 5))
			wSum += w
			dSum += d
		end
		table.insert(cells, string.format("%3.0f%%/%2.0fs", wSum / #POOL, dSum / #POOL))
	end
	print(string.format("%-10s %s", pa, table.concat(cells, " ")))
end

header("Elite check: starter Lv10 vs Thornback Boar (zone1 stage10), with/without Insight Lens")
for _, pa in STARTERS do
	local w0, d0 = matchup(function()
		return Builder.build({ petId = pa, level = 10 }, { side = "A" })
	end, function()
		return Builder.buildEnemy("ThornbackBoar", 1, 10)
	end, N)
	local w1, d1 = matchup(function()
		return Builder.build({ petId = pa, level = 10 }, { side = "A", relics = { "InsightLens" } })
	end, function()
		return Builder.buildEnemy("ThornbackBoar", 1, 10)
	end, N)
	print(
		string.format(
			"%-10s no relic %s (%.0fs)   +InsightLens %s (%.0fs)",
			pa,
			pct(w0),
			d0,
			pct(w1),
			d1
		)
	)
end

header("Relic impact: Emberfox (disadvantaged) vs Tidefrog, Lv10 mirror stats")
for _, relics in
	{
		{},
		{ "ElementWard" },
		{ "InversionPrism" },
		{ "VampiricFang" },
		{ "EchoWhistle" },
		{ "EmberHeart" },
		{ "Whetstone", "SturdyBlock" },
		{ "TimeHourglass", "EchoWhistle", "EmberHeart" },
	}
do
	local w, d = matchup(function()
		return Builder.build({ petId = "Emberfox", level = 10 }, { side = "A", relics = relics })
	end, function()
		return Builder.build({ petId = "Tidefrog", level = 10 }, { side = "B" })
	end, N)
	print(
		string.format(
			"%-40s %s  (%.0fs)",
			#relics > 0 and table.concat(relics, "+") or "(none)",
			pct(w),
			d
		)
	)
end

header("Relic marginal value: Emberfox mirror Lv10, A holds one relic (baseline ~50%)")
local relicIds = {}
for id, r in require("../src/shared/Config/Relics") do
	if type(r) == "table" and r.rarity then
		table.insert(relicIds, id)
	end
end
table.sort(relicIds)
for _, id in relicIds do
	local w, d = matchup(function()
		return Builder.build({ petId = "Emberfox", level = 10 }, { side = "A", relics = { id } })
	end, function()
		return Builder.build({ petId = "Emberfox", level = 10 }, { side = "B" })
	end, N)
	print(string.format("%-16s %s  (%.0fs)", id, pct(w), d))
end

header("Out-of-run progression: Emberfox vs Emberfox mirror, A upgraded")
for _, up in
	{
		{ label = "Lv10 vs Lv10", inst = { level = 10 } },
		{ label = "Lv15 vs Lv10", inst = { level = 15 } },
		{ label = "2 stars", inst = { level = 10, stars = 2 } },
		{ label = "Golden", inst = { level = 10, variant = "Golden" } },
		{ label = "Evolution 2", inst = { level = 10, evolution = 2 } },
	}
do
	up.inst.petId = "Emberfox"
	local w, d = matchup(function()
		return Builder.build(up.inst, { side = "A" })
	end, function()
		return Builder.build({ petId = "Emberfox", level = 10 }, { side = "B" })
	end, N)
	print(string.format("%-16s %s  (%.0fs)", up.label, pct(w), d))
end

print(string.format("\n(%.1fs total)", os.clock() - clock))
