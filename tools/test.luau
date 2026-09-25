--!nonstrict
-- Test suite for shared config + simulator. Exit code 1 on failure (used by CI).
local process = require("@lune/process")
local Pets = require("../src/shared/Config/Pets")
local Skills = require("../src/shared/Config/Skills")
local Relics = require("../src/shared/Config/Relics")
local StatusEffects = require("../src/shared/Config/StatusEffects")
local Elements = require("../src/shared/Config/Elements")
local Rarities = require("../src/shared/Config/Rarities")
local Formulas = require("../src/shared/Config/Formulas")
local Constants = require("../src/shared/Config/Constants")
local Rng = require("../src/shared/Combat/Rng")
local Builder = require("../src/shared/Combat/Builder")
local Simulator = require("../src/shared/Combat/Simulator")

local failures, passes = 0, 0
local function check(cond, msg)
	if cond then
		passes += 1
	else
		failures += 1
		print("  FAIL: " .. msg)
	end
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

print("config")
do
	local ok, err = Rarities.validateOdds()
	check(ok, "egg odds sum to 1: " .. tostring(err))
	for id, p in Pets do
		check(Elements.isValid(p.element), id .. " element valid")
		check(Rarities.StatMult[p.rarity] ~= nil, id .. " rarity valid")
		check(p.skill == nil or Skills[p.skill] ~= nil, id .. " skill exists")
		check(
			p.baseStats.hp > 0
				and p.baseStats.atk > 0
				and p.baseStats.def > 0
				and p.baseStats.spd > 0,
			id .. " base stats positive"
		)
	end
	for id, s in Skills do
		check(s.cooldown > 0, id .. " cooldown > 0")
		for _, e in s.effects do
			if e.type == "Status" then
				check(
					StatusEffects[e.status] ~= nil,
					id .. " references status " .. tostring(e.status)
				)
			end
		end
	end
	for id, r in Relics do
		if type(r) == "table" and r.rarity then
			check(Relics.Weights[r.rarity] ~= nil, id .. " relic rarity valid")
		end
	end
end

print("elements")
do
	local ADV, DIS = Constants.ELEMENT_ADVANTAGE, Constants.ELEMENT_DISADVANTAGE
	check(near(Elements.multiplier("Fire", "Grass"), ADV), "fire > grass = advantage")
	check(near(Elements.multiplier("Grass", "Fire"), DIS), "grass < fire = disadvantage")
	check(
		near(Elements.multiplier("Fire", "Water", "invert"), ADV),
		"invert flips disadvantage to advantage"
	)
	check(
		near(Elements.multiplier("Fire", "Grass", nil, "neutralize"), 1 + (ADV - 1) * 0.5),
		"neutralize softens incoming advantage"
	)
	check(
		near(Elements.multiplier("Water", "Grass", "neutralize"), 1 - (1 - DIS) * 0.5),
		"neutralize softens own disadvantage"
	)
	check(near(Elements.multiplier("Neutral", "Fire"), 1), "neutral has no matchups")
	check(
		near(Elements.multiplier("Light", "Dark", "invert", "invert"), ADV),
		"double invert cancels"
	)
end

print("formulas")
do
	check(
		near(Formulas.mitigation(50, 20), 50 / (50 + Constants.MITIGATION_K * 20)),
		"mitigation formula"
	)
	check(near(Formulas.growthMult("Rare", { level = 1 }), 2.5), "rare lvl1 growth = 2.5")
	check(
		near(
			Formulas.growthMult(
				"Common",
				{ level = 11, stars = 2, evolution = 2, variant = "Golden" }
			),
			1.5 * 1.6 * 1.2 * 1.5
		),
		"growth composes"
	)
	check(
		Formulas.formatNumber(1234567) == "1.23M",
		"formatNumber 1.23M got " .. Formulas.formatNumber(1234567)
	)
	check(Formulas.formatNumber(999) == "999", "formatNumber <1000")
	check(near(Formulas.enemyScale(2, 1), Constants.WILD_STAT_MULT * 2.5), "zone 2 = wild x2.5")
end

print("rng")
do
	local a, b = Rng.new(123), Rng.new(123)
	local same = true
	for _ = 1, 100 do
		if a:next() ~= b:next() then
			same = false
		end
	end
	check(same, "same seed -> same sequence")
	check(Rng.new(1):next() ~= Rng.new(2):next(), "different seeds differ")
	local r = Rng.new(99)
	local inRange = true
	for _ = 1, 1000 do
		local v = r:next()
		if v < 0 or v >= 1 then
			inRange = false
		end
	end
	check(inRange, "next() in [0,1)")
end

print("simulator determinism")
do
	local function run(seed)
		local a = Builder.build(
			{ petId = "Emberfox", level = 10 },
			{ side = "A", relics = { "EmberHeart", "VampiricFang" } }
		)
		local b = Builder.buildEnemy("ThornbackBoar", 1, 10)
		return Simulator.run({ seed = seed, teamA = { a }, teamB = { b } })
	end
	local function fingerprint(r)
		local parts = {}
		for _, e in r.events do
			table.insert(
				parts,
				table.concat({
					tostring(e.t),
					e.type,
					tostring(e.src),
					tostring(e.dst),
					tostring(e.amount),
					tostring(e.status),
					tostring(e.skill),
				}, ":")
			)
		end
		return table.concat(parts, "|")
	end
	local r1, r2 = run(42), run(42)
	check(fingerprint(r1) == fingerprint(r2), "same seed -> identical event log")
	check(r1.winner == r2.winner and r1.duration == r2.duration, "same seed -> identical result")
	local differs = false
	for s = 1, 5 do
		if fingerprint(run(s)) ~= fingerprint(r1) then
			differs = true
		end
	end
	check(differs, "different seeds -> different logs")
	check(#r1.events > 10, "events recorded")
end

print("simulator invariants (500 random battles)")
do
	local ids = {}
	for id in Pets do
		table.insert(ids, id)
	end
	table.sort(ids)
	local relicIds = {}
	for id, r in Relics do
		if type(r) == "table" and r.rarity then
			table.insert(relicIds, id)
		end
	end
	table.sort(relicIds)
	local rng = Rng.new(2026)
	local bad = 0
	for i = 1, 500 do
		local relics = {}
		for _ = 1, rng:int(0, 3) do
			table.insert(relics, relicIds[rng:int(1, #relicIds)])
		end
		local a = Builder.build(
			{ petId = ids[rng:int(1, #ids)], level = rng:int(1, 30), stars = rng:int(1, 3) },
			{ side = "A", relics = relics }
		)
		local b = Builder.build(
			{ petId = ids[rng:int(1, #ids)], level = rng:int(1, 30) },
			{ side = "B" }
		)
		local r = Simulator.run({ seed = i, teamA = { a }, teamB = { b }, recordEvents = false })
		if not (r.winner == "A" or r.winner == "B" or r.winner == "Draw") then
			bad += 1
		end
		if r.duration > Constants.MAX_BATTLE_SECONDS + 1e-6 then
			bad += 1
		end
		if a.hp < 0 or b.hp < 0 then
			bad += 1
		end
		if (r.winner == "A" and b.alive) or (r.winner == "B" and a.alive) then
			bad += 1
		end
	end
	check(bad == 0, "invariants held (" .. bad .. " violations)")
end

print("mechanics")
do
	-- interrupt happens with InsightLens vs a charging elite
	local hits = 0
	for seed = 1, 50 do
		local a = Builder.build(
			{ petId = "Emberfox", level = 10 },
			{ side = "A", relics = { "InsightLens" } }
		)
		local b = Builder.buildEnemy("ThornbackBoar", 1, 10)
		local r = Simulator.run({ seed = seed, teamA = { a }, teamB = { b }, recordEvents = false })
		hits += r.summary.interrupts
	end
	check(hits > 0, "Insight Lens produces interrupts (" .. hits .. ")")
	-- Second Dawn revives
	local revived = false
	for seed = 1, 20 do
		local a = Builder.build({ petId = "Dawnstag", level = 5 }, { side = "A" })
		local b = Builder.build({ petId = "Shadeclaw", level = 12 }, { side = "B" })
		local r = Simulator.run({ seed = seed, teamA = { a }, teamB = { b } })
		for _, e in r.events do
			if e.type == "Revive" then
				revived = true
			end
		end
	end
	check(revived, "Second Dawn revive event fires")
	-- Greedy Box costs HP at start
	local a = Builder.build(
		{ petId = "Tidefrog", level = 10 },
		{ side = "A", relics = { "GreedyBox" } }
	)
	local b = Builder.build({ petId = "GrassSlime", level = 1 }, { side = "B" })
	local r = Simulator.run({ seed = 1, teamA = { a }, teamB = { b } })
	check(
		r.events[2].type == "Damage" and r.events[2].status == "Curse",
		"Greedy Box start HP loss"
	)
	-- 5-slot data path: 2v2 runs without error
	local ok = pcall(function()
		Simulator.run({
			seed = 3,
			teamA = {
				Builder.build({ petId = "Emberfox", level = 5 }, { side = "A", slot = 1 }),
				Builder.build({ petId = "Mossback", level = 5 }, { side = "A", slot = 2 }),
			},
			teamB = {
				Builder.build({ petId = "GrassSlime", level = 5 }, { side = "B", slot = 1 }),
				Builder.build({ petId = "Hopcube", level = 5 }, { side = "B", slot = 2 }),
			},
			recordEvents = false,
		})
	end)
	check(ok, "multi-slot (2v2) simulation runs")
end

print(string.format("\n%d passed, %d failed", passes, failures))
if failures > 0 then
	process.exit(1)
end
