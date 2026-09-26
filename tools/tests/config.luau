--!nonstrict
-- Suite: config tables, elements, formulas, stages, camp, talents, quests and prestige rules.
local Pets = require("../../src/shared/Config/Pets")
local Skills = require("../../src/shared/Config/Skills")
local Relics = require("../../src/shared/Config/Relics")
local StatusEffects = require("../../src/shared/Config/StatusEffects")
local Elements = require("../../src/shared/Config/Elements")
local Rarities = require("../../src/shared/Config/Rarities")
local Formulas = require("../../src/shared/Config/Formulas")
local Constants = require("../../src/shared/Config/Constants")
local Stages = require("../../src/shared/Config/Stages")
local Camp = require("../../src/shared/Config/Camp")
local Talents = require("../../src/shared/Config/Talents")
local Quests = require("../../src/shared/Config/Quests")
local Prestige = require("../../src/shared/Config/Prestige")

return function(check, near)
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

	print("stages")
	do
		for _, z in Stages.Zones do
			check(
				Pets[z.elite] ~= nil and Pets[z.boss] ~= nil,
				"zone " .. z.id .. " elite/boss exist"
			)
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
		check(
			r1.coins == Stages.COIN_BASE and r1.xp == Stages.XP_BASE,
			"zone1 stage1 rewards = base"
		)
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
		check(
			Prestige.furthestIndex({ ["1-3"] = 1, ["2-4"] = 2, ["1-9"] = 0 }) == 14,
			"furthest index"
		)
		local pts = Prestige.pointsFor(30, 0)
		check(pts >= 2 and pts <= 6, "prestige points at stage 30: " .. pts)
		check(
			near(Prestige.productionMult(5), 1.4) and near(Prestige.petStatMult(5), 1.15),
			"prestige mults"
		)
	end
end
