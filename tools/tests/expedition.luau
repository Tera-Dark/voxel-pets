--!nonstrict
-- Suite: expedition map generation, relic/event pools and 60 full runs through the real simulator.
local Pets = require("../../src/shared/Config/Pets")
local Relics = require("../../src/shared/Config/Relics")
local Rng = require("../../src/shared/Combat/Rng")
local Builder = require("../../src/shared/Combat/Builder")
local Simulator = require("../../src/shared/Combat/Simulator")
local MapGen = require("../../src/shared/Expedition/MapGen")
local RelicPool = require("../../src/shared/Expedition/RelicPool")
local Events = require("../../src/shared/Expedition/Events")
local Run = require("../../src/shared/Expedition/Run")
local DataTemplate = require("../../src/shared/DataTemplate")

return function(check)
	print("expedition map")
	do
		for seed = 1, 200 do
			for floor = 1, 2 do
				local map = MapGen.generate(seed, floor, { extraTreasure = seed % 2 })
				local ok, err = MapGen.validate(map)
				check(ok, "map valid seed " .. seed .. " floor " .. floor .. ": " .. tostring(err))
				check(map.nodes[map.columns[9][1].id].kind == "Campfire", "column 9 campfire")
				for _, node in map.nodes do
					if node.enemy then
						check(Pets[node.enemy] ~= nil, "map enemy exists")
					end
				end
			end
		end
		local a, b = MapGen.generate(42, 1), MapGen.generate(42, 1)
		local same = true
		for id, n in a.nodes do
			if b.nodes[id].kind ~= n.kind or b.nodes[id].enemy ~= n.enemy then
				same = false
			end
		end
		check(same, "map generation deterministic")
		check(MapGen.generate(42, 1).nodes[2].kind ~= nil, "nodes indexable")
		-- relics
		local rng = Rng.new(5)
		local offer = RelicPool.offer(rng, { count = 3, owned = {} })
		check(#offer == 3, "3 relics offered")
		check(
			offer[1] ~= offer[2] and offer[2] ~= offer[3] and offer[1] ~= offer[3],
			"offers distinct"
		)
		local allOwned = {}
		for id, def in Relics do
			if type(def) == "table" and def.rarity then
				allOwned[id] = true
			end
		end
		check(
			#RelicPool.offer(Rng.new(1), { count = 3, owned = allOwned }) == 3,
			"offers even when all owned"
		)
		local legOnly = RelicPool.offer(Rng.new(2), { count = 3, minRarity = "Legendary" })
		for _, id in legOnly do
			check(Relics[id].rarity == "Legendary", "minRarity Legendary respected")
		end
		check(
			RelicPool.price("InsightLens", 0.2) == math.floor(RelicPool.price("InsightLens") * 0.8),
			"shop discount"
		)
		-- events
		check(#Events.List == 6, "6 events")
		for _, e in Events.List do
			check(#e.choices == 2, e.id .. " has 2 choices")
		end
		check(Events.pick(Rng.new(3), { CubeAltar = true }).id ~= nil, "event pick")
	end

	print("expedition run (60 full runs with the real simulator)")
	do
		local function battleFn(petInst)
			return function(run, node, bonuses)
				local spec = Run.enemySpec(run, node)
				local a = Builder.build(petInst, {
					side = "A",
					slot = 1,
					relics = run.relics,
					hpFraction = run.hpFraction,
					bonuses = bonuses,
				})
				local b = Builder.buildEnemy(
					spec.petId,
					spec.zone,
					spec.stage,
					{ extraMult = spec.extraMult }
				)
				return Simulator.run({
					seed = run.seed + node.id,
					teamA = { a },
					teamB = { b },
					recordEvents = false,
				})
			end
		end
		local wins, losses, floors2 = 0, 0, 0
		local relicCounts = {}
		for seed = 1, 60 do
			local pet =
				{ petId = "Emberfox", level = 12 + (seed % 3) * 6, stars = 1, evolution = 1 }
			if seed % 4 == 0 then
				pet = { petId = "Emberfox", level = 40, stars = 2, evolution = 2 } -- mid-game account
			end
			local talents = seed % 2 == 0
					and {
						E1 = true,
						S1 = true,
						S2 = true,
						S3 = true,
						S4 = true,
						S5 = true,
						A2 = true,
					}
				or {}
			local run = Run.new(seed * 31, "p1", talents)
			local policy = Rng.new(seed)
			check(run.status == "Active", "run starts active")
			if talents.E1 then
				check(
					run.pending and run.pending.type == "Relic" and run.pending.source == "Start",
					"E1 grants a start relic pick"
				)
			end
			local steps = 0
			while run.status == "Active" and steps < 200 do
				steps += 1
				if run.pending then
					local p = run.pending
					local idx
					if p.type == "Relic" then
						idx = policy:chance(0.85) and policy:int(1, #p.offers) or 0
					elseif p.type == "Shop" then
						idx = policy:chance(0.5) and 0 or policy:int(1, #p.items + 1)
					else -- Event / Campfire: two choices
						idx = policy:int(1, 2)
					end
					local ok, err = Run.choose(run, idx)
					if not ok then
						-- e.g. can't afford; leave the shop / skip
						local ok2 = Run.choose(run, 0)
						check(ok2 or p.type ~= "Shop", "shop leave always works: " .. tostring(err))
						if not ok2 then
							local ok3 = Run.choose(run, p.type == "Event" and 2 or 1)
							check(
								ok3,
								"fallback choice works for " .. p.type .. ": " .. tostring(err)
							)
						end
					end
				else
					local avail = Run.available(run)
					check(#avail > 0, "always at least one reachable node")
					local ok, err = Run.move(run, avail[policy:int(1, #avail)], battleFn(pet))
					check(ok, "move ok: " .. tostring(err))
				end
				check(
					run.hpFraction >= Run.MIN_HP - 1e-9 and run.hpFraction <= 1,
					"hp fraction within bounds"
				)
				check(run.gold >= 0, "gold never negative")
			end
			check(run.status ~= "Active", "run terminates within 200 steps")
			if run.status == "Won" then
				wins += 1
			else
				losses += 1
			end
			if run.floor >= 2 then
				floors2 += 1
			end
			for _, id in run.relics do
				check(Relics[id] ~= nil, "relic id valid")
				relicCounts[id] = (relicCounts[id] or 0) + 1
			end
			local payout = Run.payout(run)
			check(payout.marks >= 0 and payout.coins == run.gold * 2, "payout consistent")
			-- invalid actions are rejected
			local ok = Run.move(run, 1, battleFn(pet))
			check(not ok, "cannot move after run ended")
		end
		print(string.format("  runs: %d won / %d lost, reached floor 2: %d", wins, losses, floors2))
		check(
			wins > 0 and losses > 0,
			"expedition outcome is not degenerate (wins=" .. wins .. ", losses=" .. losses .. ")"
		)
		check(floors2 >= 10, "a healthy share of runs reach floor 2 (" .. floors2 .. ")")
		-- serialization round trip (profile safety): only string/number/bool/table, string keys in visited
		local run = Run.new(99, "p1", {})
		Run.move(run, Run.available(run)[1], battleFn({ petId = "Emberfox", level = 20 }))
		local function jsonSafe(v, path)
			local t = type(v)
			if t == "table" then
				local n, isArray = 0, true
				for k, x in v do
					n += 1
					if type(k) ~= "string" and type(k) ~= "number" then
						return false, path .. " bad key type"
					end
					if type(k) == "number" and (k % 1 ~= 0 or k < 1) then
						return false, path .. " non-positive-int key"
					end
					local ok, err = jsonSafe(x, path .. "." .. tostring(k))
					if not ok then
						return false, err
					end
				end
				for i = 1, n do
					if v[i] == nil then
						isArray = false
					end
				end
				if not isArray then
					for k in v do
						if type(k) == "number" then
							return false, path .. " mixed/sparse numeric keys"
						end
					end
				end
				return true
			end
			return t == "string" or t == "number" or t == "boolean", path .. " bad value type " .. t
		end
		local ok, err = jsonSafe(run, "run")
		check(ok, "run state is DataStore-safe: " .. tostring(err))
		local ok2, err2 = jsonSafe(DataTemplate, "template")
		check(ok2, "data template is DataStore-safe: " .. tostring(err2))
	end
end
