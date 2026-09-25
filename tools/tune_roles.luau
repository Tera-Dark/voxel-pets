--!nonstrict
-- Grid-searches role base-stat templates so that neutral-element role matchups sit near 50/50
-- and fight durations land in the target window. Prints the best candidates; apply by hand to
-- Config/Pets.luau (tuning is a design decision, not an automatic write).
-- usage: lune run tools/tune_roles -- [--n=150]
local process = require("@lune/process")
local Pets = require("../src/shared/Config/Pets")
local Builder = require("../src/shared/Combat/Builder")
local Simulator = require("../src/shared/Combat/Simulator")

local N = 150
for _, a in process.args do
	local n = string.match(a, "^%-%-n=(%d+)$")
	if n then
		N = tonumber(n)
	end
end
local DUR_MIN, DUR_MAX = 12, 35
-- Design target: a mild role triangle. Tank soft-counters Attacker, Attacker soft-counters
-- Support, Support outlasts Tank. (values are A's win% for A-vs-T, A-vs-S, T-vs-S)
local TARGET = { AT = 42, AS = 58, TS = 42 }

local function setTemplate(petId, t)
	local b = Pets[petId].baseStats
	b.hp, b.atk, b.def = t.hp, t.atk, t.def
end

local function matchup(pa, pb)
	local wins, dur = 0, 0
	for seed = 1, N do
		local r = Simulator.run({
			seed = seed * 7919,
			teamA = {
				Builder.build(
					{ petId = pa, level = 10 },
					{ side = "A", elementOverride = "Neutral" }
				),
			},
			teamB = {
				Builder.build(
					{ petId = pb, level = 10 },
					{ side = "B", elementOverride = "Neutral" }
				),
			},
			recordEvents = false,
		})
		if r.winner == "A" then
			wins += 1
		end
		dur += r.duration
	end
	return wins / N * 100, dur / N
end

local results = {}
local clock = os.clock()
for _, ahp in { 320, 340 } do
	for _, thp in { 440, 460, 480 } do
		for _, tatk in { 16, 17, 18 } do
			for _, tdef in { 12, 14 } do
				for _, shp in { 360, 380, 400 } do
					for _, satk in { 18, 20 } do
						setTemplate("Emberfox", { hp = ahp, atk = 20, def = 8 })
						setTemplate("Tidefrog", { hp = thp, atk = tatk, def = tdef })
						setTemplate("Mossback", { hp = shp, atk = satk, def = 11 })
						local wAT, dAT = matchup("Emberfox", "Tidefrog")
						local wAS, dAS = matchup("Emberfox", "Mossback")
						local wTS, dTS = matchup("Tidefrog", "Mossback")
						local score = math.abs(wAT - TARGET.AT)
							+ math.abs(wAS - TARGET.AS)
							+ math.abs(wTS - TARGET.TS)
						for _, d in { dAT, dAS, dTS } do
							if d < DUR_MIN then
								score += (DUR_MIN - d) * 3
							end
							if d > DUR_MAX then
								score += (d - DUR_MAX) * 3
							end
						end
						table.insert(results, {
							score = score,
							ahp = ahp,
							thp = thp,
							tatk = tatk,
							tdef = tdef,
							shp = shp,
							satk = satk,
							wAT = wAT,
							wAS = wAS,
							wTS = wTS,
							dAT = dAT,
							dAS = dAS,
							dTS = dTS,
						})
					end
				end
			end
		end
	end
end
table.sort(results, function(a, b)
	return a.score < b.score
end)
print(
	string.format(
		"%d combos, %.0fs. Best 10 (win%% A-vs-T / A-vs-S / T-vs-S, durations):",
		#results,
		os.clock() - clock
	)
)
for i = 1, 10 do
	local r = results[i]
	print(
		string.format(
			"score %5.1f | Atk hp%d | Tank hp%d atk%d def%d | Sup hp%d atk%d | %4.0f%% %4.0f%% %4.0f%% | %2.0fs %2.0fs %2.0fs",
			r.score,
			r.ahp,
			r.thp,
			r.tatk,
			r.tdef,
			r.shp,
			r.satk,
			r.wAT,
			r.wAS,
			r.wTS,
			r.dAT,
			r.dAS,
			r.dTS
		)
	)
end
