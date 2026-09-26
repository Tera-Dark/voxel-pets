--!nonstrict
-- Suite: egg odds + hatch rolls, pet instance progression, codex bonuses, feature unlocks
-- and the tutorial state machine.
local Pets = require("../../src/shared/Config/Pets")
local Rarities = require("../../src/shared/Config/Rarities")
local Eggs = require("../../src/shared/Config/Eggs")
local Formulas = require("../../src/shared/Config/Formulas")
local Rng = require("../../src/shared/Combat/Rng")
local Hatch = require("../../src/shared/Progression/Hatch")
local PetInstance = require("../../src/shared/Progression/PetInstance")
local Codex = require("../../src/shared/Progression/Codex")
local Features = require("../../src/shared/Config/Features")
local Tutorial = require("../../src/shared/Config/Tutorial")

return function(check, near)
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
			PetInstance.levelUpCost(inst)
				> PetInstance.levelUpCost(PetInstance.new("Emberfox", "x", 0)),
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
	print("features (progressive unlock)")
	do
		local fresh = { stages = {}, stats = { hatches = 0 } }
		local open = {}
		for _, f in Features.unlocked(fresh) do
			table.insert(open, f.id)
		end
		check(
			table.concat(open, ",") == "Stages,Pets",
			"new player sees only Battle + Pets: " .. table.concat(open, ",")
		)
		check(Features.nextLocked(fresh).id == "Hatch", "Hatch unlocks next")
		check(Features.requirement("Camp") == "Clear stage 1-3", "requirement text")
		check(Features.requirement("Codex") == "Hatch your first egg", "hatch requirement text")
		local mid = { stages = { ["1-1"] = 3, ["1-2"] = 2, ["1-3"] = 1 }, stats = { hatches = 1 } }
		for _, id in { "Hatch", "Codex", "Quests", "Shop", "Camp" } do
			check(Features.isUnlocked(mid, id), id .. " unlocked at 1-3 + 1 hatch")
		end
		check(not Features.isUnlocked(mid, "Expedition"), "Expedition still locked at 1-3")
		check(Features.nextLocked(mid).id == "Expedition", "Expedition is next after Camp")
		local seen, groups = {}, {}
		for _, f in Features.LIST do
			check(not seen[f.id], "unique feature id " .. f.id)
			seen[f.id] = true
			groups[f.group] = true
			check(
				type(f.icon) == "string" and type(f.blurb) == "string",
				f.id .. " has icon + blurb"
			)
		end
		for _, g in Features.GROUP_ORDER do
			check(groups[g], "group " .. g .. " used")
		end
		-- dock order keeps groups contiguous
		local last, order = nil, {}
		for _, f in Features.LIST do
			if f.group ~= last then
				check(not order[f.group], "group " .. f.group .. " contiguous in dock order")
				order[f.group] = true
				last = f.group
			end
		end
		local all = { stages = {}, stats = { hatches = 9 } }
		for z = 1, 3 do
			for st = 1, 10 do
				all.stages[z .. "-" .. st] = 3
			end
		end
		check(
			#Features.unlocked(all) == #Features.LIST and Features.nextLocked(all) == nil,
			"everything open late game"
		)
	end

	print("next stage (frontier)")
	do
		local Stages = require("../../src/shared/Config/Stages")
		local z, st = Stages.nextStage({})
		check(z == 1 and st == 1, "fresh -> 1-1")
		z, st = Stages.nextStage({ ["1-1"] = 3, ["1-2"] = 1 })
		check(z == 1 and st == 3, "after 1-2 -> 1-3")
		local zone1 = {}
		for i = 1, 10 do
			zone1["1-" .. i] = 2
		end
		z, st = Stages.nextStage(zone1)
		check(z == 2 and st == 1, "zone boss cleared -> 2-1")
		local all = {}
		for zz = 1, #Stages.Zones do
			for i = 1, 10 do
				all[zz .. "-" .. i] = 3
			end
		end
		z, st = Stages.nextStage(all)
		check(z == #Stages.Zones and st == 10, "everything cleared -> last stage")
	end

	print("tutorial state machine")
	do
		local function profile(step)
			return {
				tutorialStep = step,
				stages = {},
				stats = { hatches = 0 },
				team = { ["1"] = "p1" },
				pets = { p1 = { level = 1 } },
			}
		end
		local p = profile(0)
		check(Tutorial.progress(p) == 0 and Tutorial.isActive(p), "waits for the starter choice")
		check(Tutorial.current(p).id == "starter", "first step is the starter")
		p.stages["1-1"] = 3 -- progress made before choosing does not skip the choice
		check(Tutorial.progress(p) == 0, "starter choice cannot be skipped by progress")
		p.tutorialStep = 1
		check(Tutorial.progress(p) == 2, "1-1 already won counts immediately")
		p.tutorialStep = 2
		check(Tutorial.current(p).id == "hatch", "then hatch the free egg")
		p.stats.hatches = 1
		check(Tutorial.progress(p) == 3, "first hatch completes the hatch step")
		p.stages["1-2"] = 1
		check(Tutorial.progress(p) == Tutorial.COUNT, "hatch + 1-2 finish the tutorial")
		p.tutorialStep = Tutorial.COUNT
		check(
			not Tutorial.isActive(p) and Tutorial.current(p) == nil,
			"finished tutorial is inactive"
		)
		local skipped = profile(Tutorial.SKIPPED)
		check(
			Tutorial.progress(skipped) == Tutorial.SKIPPED and not Tutorial.isActive(skipped),
			"skip sticks"
		)
		local ordered = profile(2)
		ordered.stages["1-2"] = 1 -- later step done, earlier not: stays on the hatch step
		check(Tutorial.progress(ordered) == 2, "steps complete in order")
		check(Tutorial.COUNT == 4, "four steps")
	end
end
