--!nonstrict
-- Expedition run state machine. Pure: the run table is plain data (safe to store in a profile),
-- battles are delegated to `battleFn(run, node, bonuses) -> simResult` so the same code runs
-- on the server and in Lune tests.
local Rng = require("../Combat/Rng")
local Relics = require("../Config/Relics")
local Talents = require("../Config/Talents")
local MapGen = require("./MapGen")
local RelicPool = require("./RelicPool")
local Events = require("./Events")

local Run = {}

Run.MAX_FLOORS = 2
-- Expedition enemies are softer than the equivalent stage (relics + carry-over HP make up the rest).
-- Floor 2 draws from the zone-2 pool (2.5x zone scaling), so it gets a bigger discount.
Run.ENEMY_MULT = { 0.9, 0.7 }
Run.GOLD = { BattleMin = 20, BattleMax = 30, Elite = 50, Boss = 100, Treasure = 30, Skip = 15 }
Run.MARKS = { Battle = 1, Elite = 3, Boss = 10, Complete = 20 }
Run.CAMPFIRE_HEAL = 0.3
Run.SHOP_HEAL = 0.3
Run.SHOP_HEAL_PRICE = 40
Run.FLOOR_HEAL = 0.25
Run.SECOND_WIND_HP = 0.3
Run.MIN_HP = 0.05

local function rngOf(run)
	return Rng.fromState(run.rngState)
end

local function save(run, rng)
	run.rngState = rng.state
end

local function ownedSet(run)
	local set = {}
	for _, id in run.relics do
		set[id] = true
	end
	return set
end

local function offerRelics(run, rng, count, opts)
	opts = opts or {}
	opts.count = count
	opts.owned = ownedSet(run)
	opts.legendaryWeightBonus = (opts.legendaryWeightBonus or 0)
		+ (run.effects.legendaryWeightBonus or 0)
	return RelicPool.offer(rng, opts)
end

local function setRelicPending(run, rng, source, count, opts, remaining)
	run.pending = {
		type = "Relic",
		source = source,
		offers = offerRelics(run, rng, count, opts),
		remaining = remaining or 1,
		opts = opts or {},
		count = count,
	}
end

local function heal(run, fraction)
	run.hpFraction = math.clamp(run.hpFraction + fraction, Run.MIN_HP, 1)
end

-- ---------------------------------------------------------------- lifecycle
function Run.new(seed: number, petUid: string, talentsOwned)
	local effects = Talents.effects(talentsOwned or {})
	local rng = Rng.new(seed)
	local run = {
		seed = seed,
		petUid = petUid,
		floor = 1,
		hpFraction = 1,
		gold = 0,
		relics = {},
		map = MapGen.generate(seed, 1, { extraTreasure = effects.extraTreasure }),
		currentNodeId = 0,
		previousNodeId = 0,
		visited = {},
		pending = nil,
		afterPending = nil,
		auras = { atkMult = 1, hpMult = 1 },
		bossDamage = 0,
		nodesCleared = 0,
		battlesWon = 0,
		marks = 0,
		secondWindUsed = false,
		rerollsLeft = effects.rerollsPerFloor,
		eventsSeen = {},
		status = "Active", -- Active | Won | Lost | Abandoned
		effects = effects,
		log = {},
		rngState = 0,
	}
	if effects.startRelics > 0 then
		setRelicPending(run, rng, "Start", 3, {}, effects.startRelics)
	end
	save(run, rng)
	return run
end

function Run.available(run)
	if run.status ~= "Active" or run.pending then
		return {}
	end
	if run.currentNodeId == 0 then
		return { run.map.startId }
	end
	return run.map.nodes[run.currentNodeId].next
end

function Run.bonuses(run, node)
	local e = run.effects
	local atk = e.atkMult * run.auras.atkMult
	if node and node.kind == "Boss" then
		atk *= 1 + run.bossDamage
	end
	return { atkMult = atk, hpMult = e.hpMult * run.auras.hpMult, startShieldPct = e.startShieldPct }
end

-- Enemy scaling for a node: floor -> zone pool, column -> stage-equivalent.
function Run.enemySpec(run, node)
	return {
		petId = node.enemy,
		zone = run.map.zone,
		stage = node.col,
		extraMult = Run.ENEMY_MULT[run.floor] or Run.ENEMY_MULT[#Run.ENEMY_MULT],
	}
end

local function addLog(run, text)
	table.insert(run.log, text)
	if #run.log > 30 then
		table.remove(run.log, 1)
	end
end

local function advanceFloor(run, rng)
	run.floor += 1
	if run.floor > Run.MAX_FLOORS then
		run.status = "Won"
		run.marks += Run.MARKS.Complete
		addLog(run, "Expedition complete!")
		return
	end
	run.map = MapGen.generate(run.seed, run.floor, { extraTreasure = run.effects.extraTreasure })
	run.currentNodeId = 0
	run.visited = {}
	run.rerollsLeft = run.effects.rerollsPerFloor
	run.bossDamage = 0
	heal(run, Run.FLOOR_HEAL)
	addLog(run, "Descended to floor " .. run.floor)
	local _ = rng
end

local function resolveBattle(run, node, rng, battleFn)
	local result = battleFn(run, node, Run.bonuses(run, node))
	if result.winner == "A" then
		run.battlesWon += 1
		run.hpFraction = math.clamp(result.hpLeft.A, Run.MIN_HP, 1)
		local goldMult = 1
		for _, id in run.relics do
			goldMult *= Relics[id].runGoldMult or 1
		end
		if node.kind == "Boss" then
			run.gold += math.floor(Run.GOLD.Boss * goldMult)
			run.marks += Run.MARKS.Boss
			setRelicPending(run, rng, "Boss", 3, { legendaryWeightBonus = 20 })
			run.afterPending = "NextFloor"
		elseif node.kind == "Elite" then
			run.gold += math.floor(Run.GOLD.Elite * goldMult)
			run.marks += Run.MARKS.Elite
			setRelicPending(run, rng, "Elite", 3, { minRarity = "Rare" })
		else
			run.gold += math.floor(rng:int(Run.GOLD.BattleMin, Run.GOLD.BattleMax) * goldMult)
			run.marks += Run.MARKS.Battle
			setRelicPending(run, rng, "Battle", 3, {})
		end
		addLog(run, "Defeated " .. node.enemy)
	else
		if run.effects.secondWind and not run.secondWindUsed then
			-- Survive at 30% HP and step back: the node stays ahead and must be cleared again.
			run.secondWindUsed = true
			run.hpFraction = Run.SECOND_WIND_HP
			run.currentNodeId = run.previousNodeId or 0
			run.visited[tostring(node.id)] = nil
			addLog(run, "Second Wind! Survived the defeat.")
		else
			run.status = "Lost"
			addLog(run, "Defeated by " .. node.enemy)
		end
	end
	return result
end

-- Move to a node. Returns ok, err, simResult (only for battle nodes).
function Run.move(run, nodeId: number, battleFn)
	if run.status ~= "Active" then
		return false, "Run is over"
	end
	if run.pending then
		return false, "Resolve the current choice first"
	end
	if not table.find(Run.available(run), nodeId) then
		return false, "Node not reachable"
	end
	local node = run.map.nodes[nodeId]
	local rng = rngOf(run)
	run.previousNodeId = run.currentNodeId
	run.currentNodeId = nodeId
	run.visited[tostring(nodeId)] = true -- string keys: DataStore-safe
	run.nodesCleared += 1
	local result = nil
	if node.kind == "Battle" or node.kind == "Elite" or node.kind == "Boss" then
		result = resolveBattle(run, node, rng, battleFn)
	elseif node.kind == "Event" then
		local event = Events.pick(rng, run.eventsSeen)
		run.eventsSeen[event.id] = true
		run.pending = { type = "Event", eventId = event.id }
	elseif node.kind == "Shop" then
		local ids = offerRelics(run, rng, 3, {})
		local items = {}
		for _, id in ids do
			table.insert(
				items,
				{ relicId = id, price = RelicPool.price(id, run.effects.shopDiscount) }
			)
		end
		run.pending = {
			type = "Shop",
			items = items,
			healPrice = math.floor(Run.SHOP_HEAL_PRICE * (1 - run.effects.shopDiscount)),
			healed = false,
		}
	elseif node.kind == "Campfire" then
		run.pending = { type = "Campfire" }
	elseif node.kind == "Treasure" then
		run.gold += Run.GOLD.Treasure
		setRelicPending(run, rng, "Treasure", 2, {})
	end
	save(run, rng)
	return true, nil, result
end

local function countCommons(run)
	local n = 0
	for _, id in run.relics do
		if Relics[id].rarity == "Common" then
			n += 1
		end
	end
	return n
end

local function grantRelicOfRarity(run, rng, rarity)
	local ids = offerRelics(run, rng, 1, { minRarity = rarity, allowCursed = false })
	if ids[1] then
		table.insert(run.relics, ids[1])
		addLog(run, "Gained " .. Relics[ids[1]].displayName)
	end
end

local function applyEventEffect(run, rng, effect)
	if effect.hpPct then
		heal(run, effect.hpPct)
	end
	if effect.gold then
		run.gold = math.max(0, run.gold + effect.gold)
	end
	if effect.relic then
		grantRelicOfRarity(run, rng, effect.relic.rarity)
	end
	if effect.aura then
		for k, v in effect.aura do
			run.auras[k] = (run.auras[k] or 1) * v
		end
	end
	if effect.bossDamage then
		run.bossDamage += effect.bossDamage
	end
	if effect.fuseCommons then
		local removed = 0
		for i = #run.relics, 1, -1 do
			if removed < 2 and Relics[run.relics[i]].rarity == "Common" then
				table.remove(run.relics, i)
				removed += 1
			end
		end
		grantRelicOfRarity(run, rng, "Rare")
	end
end

local function finishPending(run, rng)
	run.pending = nil
	if run.afterPending == "NextFloor" then
		run.afterPending = nil
		advanceFloor(run, rng)
	end
end

-- Resolve the pending choice. Semantics per pending.type:
--   Relic:    1..#offers pick | 0 skip (+gold) | -1 reroll (if rerollsLeft > 0)
--   Event:    1..2 choice index
--   Shop:     1..#items buy | #items+1 heal | 0 leave
--   Campfire: 1 rest (heal) | 2 train (+5% ATK aura)
function Run.choose(run, idx: number)
	if run.status ~= "Active" then
		return false, "Run is over"
	end
	local p = run.pending
	if not p then
		return false, "Nothing to choose"
	end
	local rng = rngOf(run)
	if p.type == "Relic" then
		if idx == -1 then
			if run.rerollsLeft <= 0 then
				return false, "No rerolls left"
			end
			run.rerollsLeft -= 1
			p.offers = offerRelics(run, rng, p.count, table.clone(p.opts))
		elseif idx == 0 then
			run.gold += Run.GOLD.Skip
			p.remaining -= 1
			if p.remaining <= 0 then
				finishPending(run, rng)
			else
				p.offers = offerRelics(run, rng, p.count, table.clone(p.opts))
			end
		elseif p.offers[idx] then
			table.insert(run.relics, p.offers[idx])
			addLog(run, "Gained " .. Relics[p.offers[idx]].displayName)
			p.remaining -= 1
			if p.remaining <= 0 then
				finishPending(run, rng)
			else
				p.offers = offerRelics(run, rng, p.count, table.clone(p.opts))
			end
		else
			return false, "Bad choice"
		end
	elseif p.type == "Event" then
		local event = Events.ById[p.eventId]
		local choice = event.choices[idx]
		if not choice then
			return false, "Bad choice"
		end
		if
			choice.requires
			and choice.requires.commons
			and countCommons(run) < choice.requires.commons
		then
			return false, "Requires " .. choice.requires.commons .. " Common relics"
		end
		applyEventEffect(run, rng, choice.effect)
		addLog(run, event.title .. ": " .. choice.text)
		finishPending(run, rng)
	elseif p.type == "Shop" then
		if idx == 0 then
			finishPending(run, rng)
		elseif idx == #p.items + 1 then
			if p.healed then
				return false, "Already healed here"
			end
			if run.gold < p.healPrice then
				return false, "Not enough gold"
			end
			run.gold -= p.healPrice
			p.healed = true
			heal(run, Run.SHOP_HEAL)
		elseif p.items[idx] then
			local item = p.items[idx]
			if run.gold < item.price then
				return false, "Not enough gold"
			end
			run.gold -= item.price
			table.insert(run.relics, item.relicId)
			addLog(run, "Bought " .. Relics[item.relicId].displayName)
			table.remove(p.items, idx)
		else
			return false, "Bad choice"
		end
	elseif p.type == "Campfire" then
		if idx == 1 then
			heal(run, Run.CAMPFIRE_HEAL + run.effects.campfireBonus)
			addLog(run, "Rested at the campfire")
		elseif idx == 2 then
			run.auras.atkMult *= 1.05
			addLog(run, "Trained at the campfire (+5% ATK)")
		else
			return false, "Bad choice"
		end
		finishPending(run, rng)
	else
		return false, "Unknown pending"
	end
	save(run, rng)
	return true, nil
end

function Run.abandon(run)
	if run.status == "Active" then
		run.status = "Abandoned"
	end
end

-- Final rewards for a finished run.
function Run.payout(run)
	local mult = run.effects.marksMult
	if run.status == "Abandoned" then
		mult *= 0.5
	end
	return {
		marks = math.floor(run.marks * mult),
		coins = run.gold * 2,
		gems = run.status == "Won" and 15 or 0,
		floorsCleared = run.floor - 1,
		battlesWon = run.battlesWon,
		status = run.status,
	}
end

return Run
