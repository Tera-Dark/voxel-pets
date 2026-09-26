--!nonstrict
-- End-to-end smoke test of the server services under the Roblox API mock (tools/roblox_mock).
-- Exercises: profile load, starter grant, stages, hatching + odds, pets, camp/offline, expedition,
-- arena (bots), quests, prestige, gem shop, daily login, rate limiting, persistence.
local process = require("@lune/process")
local Mock = require("./roblox_mock")

local root = process.cwd:gsub("/$", "")
math.randomseed(20260926) -- the mock's Random.new falls back to math.random: keep runs reproducible
local M = Mock.new(root)

local failures, passes = 0, 0
local function check(cond, msg)
	if cond then
		passes += 1
	else
		failures += 1
		print("  FAIL: " .. msg)
	end
end

-- ---------------------------------------------------------------- boot (same path as Main.server.luau)
local Boot = M.load("src/server/Boot.luau")
local bootState, bootErrors = Boot.run({ world = false })
check(bootState == "ready", "server boots cleanly: " .. table.concat(bootErrors, " | "))
local Registry = M.load("src/server/Registry.luau")

local Stages = M.load("src/shared/Config/Stages.luau")
local Pets = M.load("src/shared/Config/Pets.luau")
local Data = Registry.get("DataService")
local Economy = Registry.get("EconomyService")
local PetService = Registry.get("PetService")

print("profile + starter")
local player = M.join(1001, "Tester")
local d = Data.Get(player)
check(d ~= nil, "profile loaded on join")
check(next(d.pets) ~= nil, "starter granted")
check(d.team["1"] ~= nil and d.pets[d.team["1"]] ~= nil, "starter placed in slot 1")
local starterUid = d.team["1"]
check(
	table.find(PetService.STARTERS, d.pets[starterUid].petId) ~= nil,
	"starter is one of the 3 starters"
)
local ok, _, snapshot = M.invoke("GetProfile", player)
check(ok and snapshot.coins == 0 and snapshot.pets[starterUid] ~= nil, "GetProfile snapshot")
check(#M.sent("ProfileDelta", player) >= 1, "profile replicated on load")

print("stages")
do
	local okStage, err, res = M.invoke("StartStage", player, 1, 1)
	check(okStage, "stage 1-1 runs: " .. tostring(err))
	check(res and (res.winner == "A" or res.winner == "B"), "stage result has a winner")
	local battles = M.sent("BattleResult", player)
	check(
		#battles == 1 and battles[1][1].mode == "Stage" and #battles[1][1].events > 2,
		"BattleResult payload sent with events"
	)
	check(not M.invoke("StartStage", player, 1, 3), "locked stage rejected")
	check(not M.invoke("StartStage", player, 2, 1), "locked zone rejected")
	-- grind zone 1 with a levelled starter (advance the clock past the 10-per-10s rate limit window)
	M.advance(11)
	d.pets[starterUid].level = 24 -- boss needs ~Lv17 (pve_curve); margin against element counters
	local cleared = 0
	for stage = 1, 10 do
		local okS, e2, r2 = M.invoke("StartStage", player, 1, stage)
		check(okS, "stage 1-" .. stage .. " runs: " .. tostring(e2))
		if r2 and r2.winner == "A" then
			cleared += 1
		end
	end
	check(cleared == 10, "Lv24 starter clears zone 1 (" .. cleared .. "/10)")
	M.advance(11)
	check((d.stages["1-10"] or 0) >= 1, "boss recorded with stars")
	check(d.coins > 0 and d.gems > 0, "coins + first-clear gems awarded")
	check(Stages.isZoneUnlocked(2, d.stages), "zone 2 unlocked")
	check(d.stats.battlesWon >= 10, "battlesWon stat")
end

print("hatch + odds disclosure")
do
	local okOdds, _, odds = M.invoke("GetHatchOdds", player, "MeadowEgg")
	check(okOdds and odds.available and #odds.rows > 0, "meadow egg odds available")
	local sum = 0
	for _, row in odds.rows do
		sum += row.odds
	end
	check(math.abs(sum - 1) < 1e-6, "odds rows sum to 100%")
	Economy.Add(player, "coins", 100000)
	local before = PetService.Count(player)
	local okHatch, errHatch, results = M.invoke("HatchEgg", player, "MeadowEgg", 1)
	check(okHatch, "hatch meadow egg: " .. tostring(errHatch))
	check(
		PetService.Count(player) == before + 1 and #results == 1 and Pets[results[1].petId],
		"one pet granted"
	)
	check(d.codex[results[1].petId] ~= nil, "codex registered")
	check(not M.invoke("HatchEgg", player, "MeadowEgg", 3), "triple hatch needs pass")
	d.passes.TripleHatch = true
	local ok3, err3, res3 = M.invoke("HatchEgg", player, "MeadowEgg", 3)
	check(ok3 and #res3 == 3, "triple hatch with pass: " .. tostring(err3))
	check(not M.invoke("HatchEgg", player, "VolcanoEgg", 1), "volcano egg locked before zone 3")
	-- premium egg + policy
	Economy.Add(player, "gems", 1000)
	M.paidRandomRestricted = true
	local restrictedPlayer = M.join(1002, "Restricted")
	local okP, errP = M.invoke("HatchEgg", restrictedPlayer, "PremiumEgg", 1)
	check(
		not okP and errP == "Not available in your region",
		"premium egg blocked under policy restriction"
	)
	M.paidRandomRestricted = false
	local okOddsP, _, oddsP = M.invoke("GetHatchOdds", player, "PremiumEgg")
	check(
		okOddsP and oddsP.paidRandomItem and oddsP.available,
		"premium egg flagged as paid random item"
	)
	local okPrem, errPrem = M.invoke("HatchEgg", player, "PremiumEgg", 1)
	check(okPrem, "premium hatch ok: " .. tostring(errPrem))
	-- luck potion changes disclosed odds
	local okBuy, errBuy = M.invoke("BuyWithGems", player, "LuckPotion")
	check(okBuy and d.luckCharges == 10, "luck potion bought: " .. tostring(errBuy))
	local _, _, lucky = M.invoke("GetHatchOdds", player, "MeadowEgg")
	check(
		lucky.luck > 0 and lucky.byRarity.Rare > odds.byRarity.Rare,
		"luck reflected numerically in odds"
	)
	M.invoke("HatchEgg", player, "MeadowEgg", 1)
	check(d.luckCharges == 9, "luck charge consumed")
end

print("pets")
do
	local inst = d.pets[starterUid]
	inst.level = 1
	local okL, errL = M.invoke("LevelUpPet", player, starterUid, 5)
	check(okL and inst.level == 6, "level up x5: " .. tostring(errL))
	inst.level = 30
	check(not M.invoke("LevelUpPet", player, starterUid, 1), "cannot level past cap")
	Economy.Add(player, "essence", 100)
	local okE, errE = M.invoke("EvolvePet", player, starterUid)
	check(okE and inst.evolution == 2, "evolve at cap: " .. tostring(errE))
	Economy.Add(player, "shards", 100)
	local okS = M.invoke("StarUpPet", player, starterUid)
	check(okS and inst.stars == 2, "star up")
	local okR = M.invoke("RenamePet", player, starterUid, "Sparky")
	check(okR and inst.nickname == "Sparky", "rename (filtered)")
	M.invoke("SetPetLock", player, starterUid, true)
	check(inst.locked == true, "lock")
	-- fusion: 5 GrassSlimes -> Golden
	local uids = {}
	for i = 1, 5 do
		uids[i] = PetService.Grant(player, "GrassSlime").uid
	end
	local okF, errF, newUid = M.invoke("FusePets", player, uids)
	check(okF and d.pets[newUid].variant == "Golden", "fuse -> Golden: " .. tostring(errF))
	check(d.codex.GrassSlime.Golden == true, "golden variant in codex")
	-- dismantle
	local extra = PetService.Grant(player, "Hopcube").uid
	local shardsBefore = d.shards
	local okD, errD, got = M.invoke("DismantlePets", player, { extra })
	check(
		okD and d.shards == shardsBefore + got.shards and d.pets[extra] == nil,
		"dismantle: " .. tostring(errD)
	)
	check(not M.invoke("DismantlePets", player, { starterUid }), "cannot dismantle locked/team pet")
	-- team swap
	local other = PetService.Grant(player, "Tidefrog").uid
	local okT = M.invoke("SetTeam", player, 1, other)
	check(okT and d.team["1"] == other, "set team slot 1")
	check(not M.invoke("SetTeam", player, 2, starterUid), "slot 2 locked in MVP (1v1)")
	M.invoke("SetTeam", player, 1, starterUid)
end

print("camp + offline")
do
	local worker = PetService.Grant(player, "EmberBeetle").uid
	local okC, _, camp = M.invoke("GetCamp", player)
	check(
		okC and camp.buildings.Mine.unlocked and camp.buildings.Orchard.unlocked,
		"camp snapshot; orchard unlocked after 5 stages"
	)
	local okA, errA = M.invoke("CampAssign", player, "Mine", 1, worker)
	check(okA, "assign worker: " .. tostring(errA))
	check(not M.invoke("CampAssign", player, "Mine", 2, starterUid), "team pet cannot work")
	check(not M.invoke("CampCollect", player), "nothing to collect immediately")
	M.advance(3600)
	local coinsBefore = d.coins
	local okCol, errCol, got = M.invoke("CampCollect", player)
	check(
		okCol and got.coins > 0 and d.coins == coinsBefore + got.coins,
		"collect 1h: " .. tostring(errCol) .. " coins=" .. tostring(got and got.coins)
	)
	print(string.format("  mine: 1 worker -> %d coins/hour", got.coins))
	local okU, errU = M.invoke("CampUpgrade", player, "Mine")
	check(okU and d.camp.buildings.Mine.level == 2, "upgrade mine: " .. tostring(errU))
	-- orchard xp
	local learner = PetService.Grant(player, "PuddleSnail").uid
	check(M.invoke("CampAssign", player, "Orchard", 1, learner), "assign to orchard")
	M.advance(3600 * 2)
	local _, _, got2 = M.invoke("CampCollect", player)
	check(got2 and got2.xp > 0 and d.pets[learner].level > 1, "orchard xp levels the pet")
	-- offline cap on rejoin
	M.leave(player)
	M.advance(3600 * 20)
	player = M.join(1001, "Tester")
	d = Data.Get(player)
	local reports = M.sent("OfflineReport", player)
	check(
		#reports >= 1
			and reports[#reports][1].capped == true
			and reports[#reports][1].seconds <= 8 * 3600 + 1,
		"offline report capped at 8h"
	)
	check(
		d.pets[starterUid] ~= nil and d.pets[starterUid].nickname == "Sparky",
		"profile persisted across sessions"
	)
end

print("expedition")
do
	local view
	local okX, errX
	okX, errX, view = M.invoke("GetExpedition", player)
	check(okX and view.unlocked, "expedition unlocked after 1-5")
	d.tickets = 3
	local petUid = d.team["1"]
	d.pets[petUid].level = 30
	okX, errX, view = M.invoke("ExpeditionStart", player, petUid)
	check(okX and view.run and view.run.status == "Active", "run started: " .. tostring(errX))
	check(d.tickets == 2, "ticket spent")
	check(not M.invoke("ExpeditionStart", player, petUid), "no second concurrent run")
	local steps = 0
	while view.run and view.run.status == "Active" and steps < 300 do
		steps += 1
		local run = view.run
		if run.pending then
			local idx = 1
			if run.pending.type == "Shop" then
				idx = 0
			end
			okX, errX, view = M.invoke("ExpeditionChoose", player, idx)
			if not okX then
				okX, errX, view =
					M.invoke("ExpeditionChoose", player, run.pending.type == "Event" and 2 or 0)
			end
			check(okX, "choose ok: " .. tostring(errX))
		else
			check(#view.available > 0, "reachable node exists")
			okX, errX, view = M.invoke("ExpeditionMove", player, view.available[1])
			check(okX, "move ok: " .. tostring(errX))
		end
	end
	check(view.run == nil, "run finalized and cleared")
	check(d.expedition.lastSummary ~= nil and d.marks >= 0, "summary stored")
	print(
		string.format(
			"  run ended: %s after %d steps, marks=%d",
			d.expedition.lastSummary.status,
			steps,
			d.marks
		)
	)
	local battles = M.sent("BattleResult", player)
	check(battles[#battles][1].mode == "Expedition", "expedition battles streamed to client")
	-- talents
	d.marks = 100
	local okT, errT = M.invoke("ExpeditionBuyTalent", player, "E1")
	check(okT and d.expedition.talents.E1 and d.marks == 70, "buy talent E1: " .. tostring(errT))
	check(not M.invoke("ExpeditionBuyTalent", player, "E3"), "prereq enforced")
	-- abandon path
	okX, errX, view = M.invoke("ExpeditionStart", player, petUid)
	check(okX and view.run.pending and view.run.pending.type == "Relic", "E1 start relic pending")
	okX, errX, view = M.invoke("ExpeditionAbandon", player)
	check(okX and view.run == nil, "abandon clears run")
	check(d.expedition.runs == 2, "run counter")
end

print("arena")
do
	local okO, errO, offer = M.invoke("ArenaGetOpponents", player)
	check(
		okO and #offer.opponents == 3 and offer.opponents[1].bot,
		"3 bot opponents when index is empty: " .. tostring(errO)
	)
	local ratingBefore = d.arena.rating
	local okF, errF, res = M.invoke("ArenaFight", player, 2)
	check(
		okF and res.rating ~= ratingBefore and (d.arena.wins + d.arena.losses) == 1,
		"arena fight + elo: " .. tostring(errF)
	)
	check(not M.invoke("ArenaFight", player, 2), "offer consumed")
	local okLb, _, rows = M.invoke("ArenaLeaderboard", player)
	check(okLb and type(rows) == "table", "leaderboard callable")
end

print("quests + daily + prestige")
do
	check((d.quests.progress.battlesWon or 0) >= 5, "quest progress tracked")
	local coinsBefore = d.coins
	local okQ, errQ = M.invoke("ClaimQuest", player, "WinBattles")
	check(okQ and d.coins == coinsBefore + 150, "claim quest: " .. tostring(errQ))
	check(not M.invoke("ClaimQuest", player, "WinBattles"), "no double claim")
	local okDaily, _, reward = M.invoke("ClaimDaily", player)
	check(okDaily and reward.day == 1, "daily login day 1")
	check(not M.invoke("ClaimDaily", player), "daily once per day")
	local okPv, _, preview = M.invoke("GetPrestige", player)
	check(okPv and preview.canPrestige == false, "cannot prestige yet")
	check(not M.invoke("Prestige", player), "prestige rejected")
	d.stages["3-10"] = 1
	d.stages["2-10"] = 1
	local okP, errP, res = M.invoke("Prestige", player)
	check(
		okP and res.points >= 1 and d.prestige.count == 1 and d.coins == 0 and next(d.stages) == nil,
		"prestige resets: " .. tostring(errP)
	)
	check(d.pets[starterUid] ~= nil, "pets kept after prestige")
	check(
		Registry.get("PrestigeService").ProductionMult(player) > 1,
		"production mult after prestige"
	)
end

print("rate limit + validation")
do
	local limited = false
	for _ = 1, 40 do
		local okH, errH = M.invoke("GetHatchOdds", player, "MeadowEgg")
		if not okH and errH == "Slow down" then
			limited = true
		end
	end
	check(limited, "rate limiter kicks in")
	local okBad, errBad = M.invoke("StartStage", player, "1", 1)
	check(not okBad and errBad == "Bad request", "type validation")
	local okBad2 = M.invoke("LevelUpPet", player, starterUid, 1e9)
	check(not okBad2, "range validation")
end

print(string.format("\n%d passed, %d failed", passes, failures))
if failures > 0 then
	process.exit(1)
end
