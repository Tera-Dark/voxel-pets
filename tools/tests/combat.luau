--!nonstrict
-- Suite: simulator determinism, invariants across random battles, mechanics and builder bonuses.
local Pets = require("../../src/shared/Config/Pets")
local Relics = require("../../src/shared/Config/Relics")
local Constants = require("../../src/shared/Config/Constants")
local Rng = require("../../src/shared/Combat/Rng")
local Builder = require("../../src/shared/Combat/Builder")
local Simulator = require("../../src/shared/Combat/Simulator")

return function(check, near)
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
		check(
			r1.winner == r2.winner and r1.duration == r2.duration,
			"same seed -> identical result"
		)
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
			local r =
				Simulator.run({ seed = i, teamA = { a }, teamB = { b }, recordEvents = false })
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
			local r =
				Simulator.run({ seed = seed, teamA = { a }, teamB = { b }, recordEvents = false })
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

	print("builder bonuses")
	do
		local base = Builder.build({ petId = "Emberfox", level = 10 }, { side = "A", slot = 1 })
		local boosted = Builder.build({ petId = "Emberfox", level = 10 }, {
			side = "A",
			slot = 1,
			bonuses = { atkMult = 1.1, hpMult = 1.2, startShieldPct = 0.15 },
		})
		check(boosted.atk == math.floor(base.atk * 1.1), "bonus atkMult applied")
		check(
			boosted.maxHp == math.floor(base.maxHp * 1.2) and boosted.hp == boosted.maxHp,
			"bonus hpMult applied to max and current"
		)
		check(near(boosted.mods.startShieldPct, 0.15), "bonus start shield")
		check(boosted.power > base.power, "power reflects bonuses")
	end
end
