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
local Stages = require("../src/shared/Config/Stages")
local Eggs = require("../src/shared/Config/Eggs")
local Camp = require("../src/shared/Config/Camp")
local Talents = require("../src/shared/Config/Talents")
local Quests = require("../src/shared/Config/Quests")
local Prestige = require("../src/shared/Config/Prestige")
local MapGen = require("../src/shared/Expedition/MapGen")
local RelicPool = require("../src/shared/Expedition/RelicPool")
local Events = require("../src/shared/Expedition/Events")
local Run = require("../src/shared/Expedition/Run")
local PetInstance = require("../src/shared/Progression/PetInstance")
local Hatch = require("../src/shared/Progression/Hatch")
local Codex = require("../src/shared/Progression/Codex")
local DataTemplate = require("../src/shared/DataTemplate")
local Network = require("../src/shared/Network")

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
	check(
		near(Formulas.enemyScale(2, 1), Constants.WILD_STAT_MULT * Constants.ZONE_STAT_MULT),
		"zone 2 = wild x zone mult"
	)
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

print("stages")
do
	for _, z in Stages.Zones do
		check(Pets[z.elite] ~= nil and Pets[z.boss] ~= nil, "zone " .. z.id .. " elite/boss exist")
		for _, id in z.pool do
			check(Pets[id] ~= nil, "zone " .. z.id .. " pool pet " .. id .. " exists")
		end
		for stage = 1, Stages.STAGES_PER_ZONE do
			local enemy, kind = Stages.enemyFor(z.id, stage)
			check(Pets[enemy] ~= nil, "enemy exists " .. z.id .. "-" .. stage)
			if stage == 10 then
				check(kind == "Boss", "stage 10 is boss")
			elseif stage == 5 then
				check(kind == "Elite", "stage 5 is elite")
			end
		end
	end
	local r1, r10 = Stages.rewards(1, 1), Stages.rewards(1, 10)
	check(r1.coins == Stages.COIN_BASE and r1.xp == Stages.XP_BASE, "zone1 stage1 rewards = base")
	check(r10.coins > r1.coins * 5, "boss rewards scale")
	check(r10.firstClearGems == 25, "boss first clear 25 gems")
	local data = {}
	check(Stages.isStageUnlocked(1, 1, data), "1-1 unlocked initially")
	check(not Stages.isStageUnlocked(1, 2, data), "1-2 locked initially")
	check(not Stages.isZoneUnlocked(2, data), "zone 2 locked initially")
	data["1-10"] = 1
	check(Stages.isZoneUnlocked(2, data), "zone 2 unlocked after 1-10")
	check(Stages.starsFor({ winner = "A", duration = 20 }, 0.8) == 3, "3 stars fast+healthy")
	check(Stages.starsFor({ winner = "A", duration = 50 }, 0.2) == 1, "1 star slow+low")
	check(Stages.starsFor({ winner = "B", duration = 10 }, 1) == 0, "0 stars on loss")
end

print("eggs + hatch")
do
	for eggId, egg in Eggs do
		check(Rarities.EggOdds[eggId] ~= nil, eggId .. " has odds")
		for rarity, pool in egg.pool do
			for _, petId in pool do
				check(Pets[petId] ~= nil, eggId .. " pool pet exists " .. petId)
				check(
					Pets[petId].rarity == rarity,
					eggId .. " " .. petId .. " listed under its rarity " .. rarity
				)
				check(
					not Pets[petId].expeditionOnly or eggId == "PremiumEgg",
					petId .. " expedition-only not in zone egg"
				)
			end
		end
		for rarity, p in Rarities.EggOdds[eggId] do
			check(
				p == 0 or (egg.pool[rarity] and #egg.pool[rarity] > 0),
				eggId .. " has pool for " .. rarity
			)
		end
		local rows, byRarity, sum = Hatch.disclosure(eggId, 0)
		check(near(sum, 1, 1e-6), eggId .. " disclosure sums to 100% (" .. sum .. ")")
		check(
			#rows > 0 and byRarity.Common ~= nil or eggId == "PremiumEgg",
			eggId .. " disclosure rows"
		)
		local rowsL, _, sumL = Hatch.disclosure(eggId, 0.5)
		check(near(sumL, 1, 1e-6), eggId .. " lucky disclosure sums to 100%")
		check(#rowsL == #rows, "luck does not change outcome list")
	end
	local base = Rarities.EggOdds.MeadowEgg
	local lucky = Hatch.oddsWithLuck(base, 1.0)
	check(near(lucky.Rare, base.Rare * 2), "luck 1.0 doubles Rare")
	check(lucky.Common < base.Common, "luck takes mass from Common")
	local rng = Rng.new(7)
	local counts, mismatches = {}, 0
	for _ = 1, 20000 do
		local petId, rarity = Hatch.roll(rng, "MeadowEgg", 0)
		if Pets[petId].rarity ~= rarity then
			mismatches += 1
		end
		counts[rarity] = (counts[rarity] or 0) + 1
	end
	check(mismatches == 0, "rolled pet rarity always matches rolled rarity")
	check(
		math.abs(counts.Common / 20000 - 0.55) < 0.02,
		"empirical Common ~55%: " .. counts.Common / 20000
	)
	check(math.abs((counts.Rare or 0) / 20000 - 0.12) < 0.015, "empirical Rare ~12%")
	local prem = Hatch.roll(Rng.new(1), "PremiumEgg", 0)
	check(
		Rarities.StatMult[Pets[prem].rarity] >= Rarities.StatMult.Rare,
		"premium egg never below Rare"
	)
end

print("camp")
do
	check(
		Camp.slots("Mine", 1) == 3 and Camp.slots("Mine", 6) == 4,
		"mine slots grow every 5 levels"
	)
	check(Camp.slots("Mine", 200) == 10, "mine slots capped")
	local rateFire = Camp.workerRate("Mine", 1, { power = 100, element = "Fire" })
	local rateGrass = Camp.workerRate("Mine", 1, { power = 100, element = "Grass" })
	check(near(rateFire, rateGrass * 1.25), "affinity +25%")
	check(
		near(Camp.workerRate("Mine", 2, { power = 100, element = "Grass" }), rateGrass * 1.15),
		"level mult 1.15"
	)
	check(
		Camp.upgradeCost("Mine", 1) == 200 and Camp.upgradeCost("Mine", 2) == 250,
		"upgrade cost curve"
	)
	check(
		Camp.isUnlocked("Mine", {}) and not Camp.isUnlocked("Orchard", {}),
		"orchard locked at start"
	)
	check(Camp.isUnlocked("Orchard", { stagesCleared = 5 }), "orchard unlock at 5 stages")
	local hourly = rateGrass * 3600
	check(hourly > 50 and hourly < 5000, "1 worker (power 100) hourly coins sane: " .. hourly)
end

print("talents")
do
	check(#Talents.Nodes == 15, "15 talent nodes")
	local owned = {}
	local ok, err = Talents.canBuy("E2", owned, 999)
	check(not ok and err == "requires E1", "prereq enforced")
	check(Talents.canBuy("E1", owned, 30), "E1 affordable at 30")
	check(not Talents.canBuy("E1", owned, 29), "E1 unaffordable at 29")
	owned.E1 = true
	check(not Talents.canBuy("E1", owned, 999), "no double buy")
	owned.S1, owned.S3, owned.A2 = true, true, true
	local e = Talents.effects(owned)
	check(
		e.startRelics == 1
			and near(e.hpMult, 1.1)
			and near(e.atkMult, 1.1)
			and near(e.marksMult, 1.2),
		"effects fold"
	)
	check(e.secondWind == false, "unowned bool stays false")
end

print("quests + prestige")
do
	check(#Quests.Daily == 6, "6 dailies")
	for _, q in Quests.Daily do
		check(q.goal > 0 and (q.reward.coins or q.reward.gems), q.id .. " valid")
	end
	check(#Quests.dateKey(0) == 10, "date key format")
	check(not Prestige.canPrestige({ ["2-10"] = 3 }), "no prestige before zone 3 boss")
	check(Prestige.canPrestige({ ["3-10"] = 1 }), "prestige after zone 3 boss")
	check(Prestige.furthestIndex({ ["1-3"] = 1, ["2-4"] = 2, ["1-9"] = 0 }) == 14, "furthest index")
	local pts = Prestige.pointsFor(30, 0)
	check(pts >= 2 and pts <= 6, "prestige points at stage 30: " .. pts)
	check(
		near(Prestige.productionMult(5), 1.4) and near(Prestige.petStatMult(5), 1.15),
		"prestige mults"
	)
end

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
	check(offer[1] ~= offer[2] and offer[2] ~= offer[3] and offer[1] ~= offer[3], "offers distinct")
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
		local pet = { petId = "Emberfox", level = 12 + (seed % 3) * 6, stars = 1, evolution = 1 }
		if seed % 4 == 0 then
			pet = { petId = "Emberfox", level = 40, stars = 2, evolution = 2 } -- mid-game account
		end
		local talents = seed % 2 == 0
				and { E1 = true, S1 = true, S2 = true, S3 = true, S4 = true, S5 = true, A2 = true }
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
						check(ok3, "fallback choice works for " .. p.type .. ": " .. tostring(err))
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

print("pet instance")
do
	local inst = PetInstance.new("Emberfox", "u1", 0)
	check(inst.level == 1 and inst.variant == "Normal", "new instance defaults")
	local gained = PetInstance.addXp(inst, Formulas.xpForLevel(1) + Formulas.xpForLevel(2))
	check(gained == 2 and inst.level == 3 and inst.xp == 0, "xp levels up twice")
	PetInstance.addXp(inst, 1e9)
	check(inst.level == 30, "capped at evolution 1 cap (30)")
	check(not PetInstance.canLevelUp(inst), "cannot buy level at cap")
	check(PetInstance.canEvolve(inst), "can evolve at cap")
	check(PetInstance.evolveCost(inst).essence == 10, "evolve cost stage 1")
	inst.evolution = 2
	check(PetInstance.levelCap(inst) == 60, "cap 60 after evolve")
	check(
		PetInstance.levelUpCost(inst) > PetInstance.levelUpCost(PetInstance.new("Emberfox", "x", 0)),
		"cost grows"
	)
	local common = PetInstance.new("GrassSlime", "c", 0)
	check(
		PetInstance.levelUpCost(common)
			< PetInstance.levelUpCost(PetInstance.new("Emberfox", "x", 0)),
		"common cheaper"
	)
	check(PetInstance.dismantleValue(common).shards == 5, "common dismantle 5 shards")
	local five = {}
	for i = 1, 5 do
		five[i] = PetInstance.new("GrassSlime", "g" .. i, 0)
	end
	five[3].level = 9
	check(PetInstance.canFuse(five), "5 same commons fuse")
	local fused = PetInstance.fuseResult(five, "new", 0)
	check(fused.variant == "Golden" and fused.level == 9, "fusion -> Golden keeps best level")
	five[5].petId = "Hopcube"
	check(not PetInstance.canFuse(five), "mixed species cannot fuse")
	check(PetInstance.power(inst) > 0, "power computed")
	check(PetInstance.power(inst, 1.1) > PetInstance.power(inst), "global mult raises power")
end

print("builder bonuses")
do
	local base = Builder.build({ petId = "Emberfox", level = 10 }, { side = "A", slot = 1 })
	local boosted = Builder.build(
		{ petId = "Emberfox", level = 10 },
		{ side = "A", slot = 1, bonuses = { atkMult = 1.1, hpMult = 1.2, startShieldPct = 0.15 } }
	)
	check(boosted.atk == math.floor(base.atk * 1.1), "bonus atkMult applied")
	check(
		boosted.maxHp == math.floor(base.maxHp * 1.2) and boosted.hp == boosted.maxHp,
		"bonus hpMult applied to max and current"
	)
	check(near(boosted.mods.startShieldPct, 0.15), "bonus start shield")
	check(boosted.power > base.power, "power reflects bonuses")
end

print("codex")
do
	local codex = {}
	check(Codex.register(codex, "Emberfox"), "register new")
	check(not Codex.register(codex, "Emberfox"), "no double register")
	check(Codex.register(codex, "Emberfox", "Golden"), "register variant")
	local s = Codex.summary(codex)
	check(s.species == 1 and s.variants == 1 and s.totalSpecies == 34, "summary counts")
	check(near(Codex.bonusMult(codex), 1.005), "bonus 0.3% + 0.2%")
	for _, id in Codex.zoneSpecies(1) do
		Codex.register(codex, id)
	end
	check(Codex.isZoneComplete(codex, 1), "zone 1 complete")
	check(Codex.bonusMult(codex) > 1.03, "zone bonus applied")
end

print("data + network")
do
	check(DataTemplate.schemaVersion == 1, "schema v1")
	for _, key in DataTemplate.PUBLIC_KEYS do
		check(DataTemplate[key] ~= nil, "public key exists in template: " .. key)
	end
	local seen = {}
	for _, name in Network.Functions do
		check(not seen[name], "unique remote " .. name)
		seen[name] = true
	end
	for _, name in Network.Events do
		check(not seen[name], "unique remote " .. name)
		seen[name] = true
	end
	check(#Network.Functions >= 30, "function list complete")
end

print(string.format("\n%d passed, %d failed", passes, failures))
if failures > 0 then
	process.exit(1)
end
