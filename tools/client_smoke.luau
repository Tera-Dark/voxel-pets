--!nonstrict
-- Client end-to-end smoke test: the real client scripts (src/client) run against the real server
-- services (tools/roblox_mock, scheduler mode) through tools/client_mock. Boots like a Studio
-- play-test of an unpublished place (offline save mode), then opens every screen and walks the
-- main flows by "clicking" buttons. Any client error, broken screen or remote payload that
-- Roblox would mangle fails the run.
local process = require("@lune/process")
local Mock = require("./roblox_mock")
local ClientMock = require("./client_mock")

local root = process.cwd:gsub("/$", "")
local VERBOSE = table.find(process.args, "--verbose") ~= nil

local failures, passes = 0, 0
local function check(cond, msg)
	if cond then
		passes += 1
	else
		failures += 1
		print("  FAIL: " .. msg)
	end
end

math.randomseed(20260926)
local M = Mock.new(root, { scheduler = true, placeId = 0 })
local Boot = M.load("src/server/Boot.luau")
M.spawn(function()
	Boot.run({ world = false })
end)
M.advance(0.1)

local CM = ClientMock.new(M, root, { userId = 3001, name = "Tester" })
local Registry = M.load("src/server/Registry.luau")
local Data = Registry.get("DataService")
local seenErrors = 0

-- Reports client errors raised since the last call (so each flow fails on its own errors).
local function noNewErrors(label)
	local new = {}
	for i = seenErrors + 1, #CM.errors do
		table.insert(new, CM.errors[i])
	end
	seenErrors = #CM.errors
	check(#new == 0, label .. " raised client errors:\n    " .. table.concat(new, "\n    "))
end

local function give(fields)
	local d = Data.Get(CM.serverPlayer)
	local keys = {}
	for k, v in fields do
		d[k] = v
		table.insert(keys, k)
	end
	Data.ReplicateKeys(CM.serverPlayer, keys)
	M.advance(0.2)
end

-- ---------------------------------------------------------------- boot
print("boot")
CM.start()
M.advance(0.05)
check(CM.byText("v0.") ~= nil, "loading screen shows the build version")
M.advance(4)
check(CM.playerGui:FindFirstChild("VoxelPetsUI") ~= nil, "main UI built")
M.advance(1)
check(CM.playerGui:FindFirstChild("VoxelPetsBoot") == nil, "loading screen removed")
check(CM.byText("TEST MODE") ~= nil, "offline banner shown in an unpublished place")
check(table.find(CM.prints, "[VoxelPets] client ready") ~= nil, "client reached ready")
local buildLabel = CM.playerGui.VoxelPetsUI:FindFirstChild("BuildLabel")
check(buildLabel ~= nil and string.sub(buildLabel.Text, 1, 2) == "v0", "build stamp in the corner")
noNewErrors("boot")

local Screens = CM.require("src/client/UI/ScreenManager.luau")
local State = CM.require("src/client/State.luau")
local Highlight = CM.require("src/client/UI/Highlight.luau")
check(State.loaded and State.profile and next(State.profile.pets) ~= nil, "profile with starter")

local function named(name)
	return CM.find(function(d)
		return d.Name == name and CM.visible(d)
	end)
end
local function dockIds()
	local ids = {}
	for _, d in CM.descendants() do
		if string.sub(d.Name, 1, 5) == "Dock_" and CM.visible(d) then
			table.insert(ids, string.sub(d.Name, 6))
		end
	end
	table.sort(ids)
	return table.concat(ids, ",")
end
local function highlightTarget()
	local target = Highlight.current()
	return target and target.Name or nil
end
local function goalText()
	local g = named("GoalTracker")
	return g and CM.text(g:FindFirstChild("Goal")) or ""
end

-- ---------------------------------------------------------------- first-time HUD
print("first-time HUD (progressive unlock)")
do
	check(dockIds() == "Pets", "a new player's dock holds just Pets: " .. dockIds())
	check(named("BattleButton") ~= nil, "BATTLE is the big entry point (not a dock tile)")
	check(named("Pill_coins") ~= nil and named("Pill_gems") ~= nil, "coins + gems pills")
	check(named("Pill_essence") == nil, "no wall of zero currencies")
	CM.click(named("MoreCurrencies"), 0.2)
	local drop = named("CurrencyDrop")
	check(drop ~= nil and CM.byText("Essence", nil, drop) ~= nil, "+ reveals other currencies")
	check(
		drop ~= nil and CM.byText("Tickets", nil, drop) == nil,
		"locked-feature currencies stay hidden"
	)
	CM.click(named("MoreCurrencies"), 0.2)
	check(named("CurrencyDrop") == nil, "+ collapses again")
	check(named("SettingsButton") ~= nil, "settings gear")
	check(CM.byText("Choose your partner!") ~= nil, "partner picker opens for a new player")
	check(
		goalText() == "Choose your partner",
		"goal tracker: choose partner (" .. goalText() .. ")"
	)
	noNewErrors("first-time HUD")
end

-- ---------------------------------------------------------------- tutorial
print("tutorial")
do
	local choose = CM.find(function(d)
		return d.Name == "Choose"
			and d.Parent
			and d.Parent.Name == "Starter_Tidefrog"
			and CM.visible(d)
	end)
	check(choose ~= nil, "Tidefrog card has CHOOSE")
	CM.click(choose, 0.6)
	local p = State.profile
	check(p.pets[p.team["1"]].petId == "Tidefrog", "partner swapped to Tidefrog")
	check(p.tutorialStep == 1, "tutorial step 1")
	check(CM.byText("Choose your partner!") == nil, "picker closed")
	check(goalText() == "Win your first battle", "goal: first battle (" .. goalText() .. ")")
	check(
		highlightTarget() == "BattleButton",
		"pointer on BATTLE (" .. tostring(highlightTarget()) .. ")"
	)

	CM.click(named("BattleButton"), 0.6)
	check(Screens.current() == "Stages", "BATTLE opens the stage list")
	check(
		highlightTarget() == "FightButton",
		"pointer on FIGHT (" .. tostring(highlightTarget()) .. ")"
	)
	CM.click(named("FightButton"), 1)
	check(Screens.current() == "Battle", "battle plays")
	CM.click(CM.byText("SKIP", "TextButton"), 2)
	CM.click(CM.byText("Close", "TextButton"), 0.6)
	check(State.profile.tutorialStep == 2, "win -> step 2")
	check(dockIds() == "Hatch,Pets", "Hatch unlocked after the first win: " .. dockIds())
	local hatchItem = named("Dock_Hatch")
	check(hatchItem and hatchItem.New.Visible, "Hatch shows NEW")
	check(hatchItem and hatchItem.Badge.Visible, "Hatch badge: free egg waiting")
	check(
		highlightTarget() == "Dock_Hatch",
		"pointer on Hatch (" .. tostring(highlightTarget()) .. ")"
	)

	CM.click(hatchItem, 0.8)
	check(Screens.current() == "Hatch", "Hatch opened from the dock")
	check(
		highlightTarget() == "HatchFree",
		"pointer on the free hatch (" .. tostring(highlightTarget()) .. ")"
	)
	local coins = State.profile.coins
	CM.click(named("HatchFree"), 1)
	check(CM.byText("Hatched!") ~= nil, "hatch result")
	check(State.profile.coins == coins and State.profile.freeHatches == 0, "free egg cost nothing")
	CM.run(function()
		CM.require("src/client/UI/Components.luau").closeTopModal()
	end, 0.3)
	check(CM.byText("Hatched!") == nil, "Esc path closes the top window")
	CM.run(function()
		Screens.close()
	end, 0.4)
	check(State.profile.tutorialStep == 3, "hatch -> step 3")
	check(string.find(dockIds(), "Codex", 1, true) ~= nil, "Codex unlocked by the first hatch")
	check(goalText() == "Win stage 1-2", "goal: 1-2 (" .. goalText() .. ")")

	CM.click(named("BattleButton"), 0.6)
	check(CM.byText("FIGHT 1-2", "TextButton") ~= nil, "BATTLE jumps to the next stage (1-2)")
	local gems = State.profile.gems
	CM.click(named("FightButton"), 1)
	CM.click(CM.byText("SKIP", "TextButton"), 2)
	CM.click(CM.byText("Close", "TextButton"), 0.8)
	check(State.profile.tutorialStep == 4, "tutorial complete")
	check(State.profile.gems >= gems + 50, "tutorial reward")
	check(CM.byText("Tutorial complete!") ~= nil, "celebration shown")
	check(highlightTarget() == nil, "pointer gone")
	check(dockIds() == "Codex,Hatch,Pets,Quests,Shop", "Quests + Shop open: " .. dockIds())
	local goalTitle = CM.text(named("GoalTracker"):FindFirstChild("Title"))
	check(
		string.find(goalTitle, "CAMP", 1, true) ~= nil,
		"next goal points at Camp (" .. goalTitle .. ")"
	)
	check(goalText() == "Clear stage 1-3", "goal line says how (" .. goalText() .. ")")
	CM.click(CM.byText("LET'S GO", "TextButton"), 0.3)
	noNewErrors("tutorial")
end

-- ---------------------------------------------------------------- dock behaviour + unlocks
print("dock")
do
	CM.click(named("DockToggle"), 0.2)
	check(named("Dock_Pets") == nil, "dock collapses")
	check(CM.text(named("DockToggle")) == "^  MENU", "collapsed dock leaves a MENU tab")
	CM.click(named("DockToggle"), 0.2)
	check(named("Dock_Pets") ~= nil, "dock expands again")
	CM.click(named("Dock_Pets"), 0.6)
	check(
		Screens.current() == "Pets" and named("Dock_Pets") == nil,
		"dock steps aside while a screen is open"
	)
	CM.run(function()
		Screens.close()
	end, 0.3)
	check(named("Dock_Pets") ~= nil, "closing the screen brings the dock back")
	local stages = {}
	for s = 1, 3 do
		stages["1-" .. s] = 3
	end
	M.advance(6) -- real pacing: nobody clears 1-3 within seconds of finishing the tutorial
	give({ stages = stages })
	check(string.find(dockIds(), "Camp", 1, true) ~= nil, "Camp unlocks at 1-3")
	M.advance(0.8) -- banners wait a moment (see HUD.unlockBanners)
	check(CM.byText("NEW: Camp unlocked!") ~= nil, "unlock banner")
	check(named("Dock_Camp").New.Visible, "Camp shows NEW")
	local all = {}
	for zz = 1, 2 do
		for s = 1, 10 do
			all[zz .. "-" .. s] = 3
		end
	end
	give({ stages = all })
	check(#string.split(dockIds(), ",") == 9, "everything open late game (9 tiles): " .. dockIds())
	noNewErrors("dock")
end

-- ---------------------------------------------------------------- every screen opens
print("screens")
for _, name in
	{
		"Pets",
		"Hatch",
		"Stages",
		"Camp",
		"Expedition",
		"Arena",
		"Codex",
		"Quests",
		"Shop",
		"Prestige",
	}
do
	CM.run(function()
		Screens.open(name)
	end, 1)
	check(Screens.current() == name, name .. " is the current screen")
	local broken = CM.find(function(d)
		return string.sub(d.Name, -6) == "_Error" and CM.visible(d)
	end)
	check(broken == nil, name .. " built without an error panel")
	noNewErrors("open " .. name)
	CM.run(function()
		Screens.close()
	end, 0.2)
end

-- ---------------------------------------------------------------- helpers for flows
local function openScreen(name, arg)
	CM.run(function()
		Screens.open(name, arg)
	end, 0.6)
end

-- Top-most visible modal close button ("X" at ZIndex >= 53), if any.
local function closeModal()
	local best = nil
	for _, b in
		CM.findAll(function(d)
			return d.ClassName == "TextButton"
				and CM.text(d) == "X"
				and CM.visible(d)
				and d.ZIndex >= 53
		end)
	do
		if not best or b.ZIndex > best.ZIndex then
			best = b
		end
	end
	if best then
		CM.click(best, 0.2)
	end
	return best ~= nil
end

local function button(text)
	return CM.byText(text, "TextButton")
end

local function petCount()
	local n = 0
	for _ in State.profile.pets do
		n += 1
	end
	return n
end

-- Plays the battle that just started: SKIP, then the named result action.
local function finishBattle(label, action)
	check(Screens.current() == "Battle", label .. ": battle screen opened")
	local skip = button("SKIP")
	check(skip ~= nil, label .. ": skip button")
	if skip then
		CM.click(skip, 2)
	end
	local act = button(action or "Close")
	check(act ~= nil, label .. ": result action '" .. (action or "Close") .. "'")
	if act then
		CM.click(act, 0.6)
	end
end

-- ---------------------------------------------------------------- stage battle (skip + real time)
print("stage battles")
do
	openScreen("Stages", { zone = 1, stage = 1 })
	local fight = button("FIGHT")
	check(fight ~= nil, "FIGHT button on the stage preview")
	CM.click(fight, 1)
	finishBattle("1-1 skip", "Close")
	check(Screens.current() == nil, "battle closed")
	check((Data.Get(CM.serverPlayer).stages["1-1"] or 0) > 0, "1-1 cleared on the server")
	noNewErrors("stage battle (skip)")

	openScreen("Stages", { zone = 1, stage = 1 })
	CM.click(button("FIGHT"), 1)
	M.advance(90) -- real-time playback through Heartbeat
	local nextBtn = button("Next")
	check(nextBtn ~= nil, "result shown after real-time playback")
	if nextBtn then
		CM.click(nextBtn, 0.6)
		check(Screens.current() == "Stages", "Next opens the stage list")
	end
	noNewErrors("stage battle (real time)")
end

-- ---------------------------------------------------------------- hatch
print("hatch")
do
	give({ coins = 200000 })
	openScreen("Hatch")
	CM.click(button("Details (odds)"), 0.3)
	check(CM.byText("%") ~= nil, "odds modal lists percentages")
	check(closeModal(), "odds modal closes")
	local before = petCount()
	CM.click(button("Hatch x1"), 1)
	check(CM.byText("Hatched!") ~= nil, "hatch result modal")
	closeModal()
	check(petCount() == before + 1, "hatched pet arrives in the client state")
	noNewErrors("hatch")
end

-- ---------------------------------------------------------------- pets
print("pets")
do
	openScreen("Pets")
	local uid = State.profile.team["1"]
	local lvl = State.profile.pets[uid].level
	CM.click(button("Level +1"), 0.6)
	check(State.profile.pets[uid].level == lvl + 1, "level up via the detail panel")
	CM.click(button("Lock"), 0.4)
	noNewErrors("pets")
end

-- ---------------------------------------------------------------- camp
print("camp")
do
	openScreen("Camp")
	local assign = button("+ assign pet")
	check(assign ~= nil, "empty worker slot")
	CM.click(assign, 0.4)
	local pick = CM.find(function(d)
		return d.ClassName == "TextButton"
			and d.ZIndex == 53
			and CM.visible(d)
			and string.find(CM.text(d), "Lv", 1, true) ~= nil
	end)
	check(pick ~= nil, "pet picker lists an idle pet")
	if pick then
		CM.click(pick, 0.8)
	end
	local workers = 0
	for _, b in Data.Get(CM.serverPlayer).camp.buildings do
		workers += #b.workers
	end
	check(workers == 1, "worker assigned on the server")
	M.advance(60)
	CM.click(button("COLLECT"), 0.6)
	noNewErrors("camp")
	CM.run(function()
		Screens.close()
	end, 0.2)
end

-- ---------------------------------------------------------------- quests + daily
print("quests")
do
	openScreen("Quests")
	local gems = State.profile.gems or 0
	local claim = button("CLAIM DAILY REWARD")
	check(claim ~= nil, "daily reward button")
	if claim then
		CM.click(claim, 0.6)
	end
	check((State.profile.gems or 0) >= gems, "daily claim applied")
	noNewErrors("quests")
end

-- ---------------------------------------------------------------- arena
print("arena")
do
	openScreen("Arena")
	local fight = button("FIGHT")
	check(fight ~= nil, "arena opponents listed")
	if fight then
		CM.click(fight, 1)
		finishBattle("arena", "Arena")
	end
	noNewErrors("arena")
end

-- ---------------------------------------------------------------- shop
print("shop")
do
	give({ gems = 500 })
	openScreen("Shop")
	local buy = CM.find(function(d)
		return d.ClassName == "TextButton"
			and CM.visible(d)
			and string.find(CM.text(d), " gems", 1, true) ~= nil
	end)
	check(buy ~= nil, "gem shop item")
	if buy then
		CM.click(buy, 0.6)
	end
	check((State.profile.gems or 0) < 500, "gem purchase applied")
	noNewErrors("shop")
end

-- ---------------------------------------------------------------- settings (HUD)
print("settings")
do
	CM.run(function()
		Screens.close()
	end, 0.2)
	CM.click(named("SettingsButton"), 0.4)
	local toggle = button("Auto-skip battles")
	check(toggle ~= nil, "settings modal")
	if toggle then
		CM.click(toggle, 0.4)
	end
	closeModal()
	noNewErrors("settings")
end

-- ---------------------------------------------------------------- expedition (walk a whole run)
print("expedition")
do
	local stages = {}
	for s = 1, 5 do
		stages["1-" .. s] = 3
	end
	give({ stages = stages, tickets = 3 })
	openScreen("Expedition")
	local start = button("START EXPEDITION")
	check(start ~= nil and start.Active, "start button enabled after 1-5")
	CM.click(start, 0.4)
	local pick = CM.find(function(d)
		return d.ClassName == "TextButton"
			and d.ZIndex == 53
			and CM.visible(d)
			and string.find(CM.text(d), "Lv", 1, true) ~= nil
	end)
	check(pick ~= nil, "expedition pet picker")
	if pick then
		CM.click(pick, 1)
	end
	local d = Data.Get(CM.serverPlayer)
	check(d.expedition.run ~= nil, "run started on the server")
	local screenFrame = CM.find(function(x)
		return x.Name == "Expedition" and CM.visible(x)
	end)
	local steps, battles = 0, 0
	while d.expedition.run ~= nil and steps < 60 do
		steps += 1
		if Screens.current() == "Battle" then
			battles += 1
			finishBattle("expedition battle " .. battles, "Map")
		else
			local pending = screenFrame and screenFrame:FindFirstChild("Pending")
			local target = nil
			if pending and CM.visible(pending) then
				target = CM.buttons(pending)[1]
			end
			if not target then
				local map = screenFrame and screenFrame:FindFirstChild("Map")
				local reachable = CM.require("src/client/UI/PixelTheme.luau").Colors.good
				for _, b in CM.buttons(map) do
					if b.BackgroundColor3 == reachable then -- green = reachable next node
						target = b
						break
					end
				end
			end
			if not target then
				break
			end
			if VERBOSE then
				local run = d.expedition.run
				print(
					string.format(
						"    step %d: click %q (node %s, pending %s)",
						steps,
						string.gsub(CM.text(target), "\n", " "),
						tostring(run and run.currentNodeId),
						tostring(run and run.pending and run.pending.kind)
					)
				)
			end
			CM.click(target, 1)
		end
	end
	check(
		d.expedition.run == nil,
		"expedition run completed through the UI (" .. steps .. " steps)"
	)
	check(battles >= 1, "expedition battles played")
	noNewErrors("expedition")
	openScreen("Expedition")
	noNewErrors("expedition summary")
end

-- ---------------------------------------------------------------- fuzz: every button on every screen
print("fuzz")
do
	local SKIP = { ["PRESTIGE"] = true, ["X"] = true }
	for _, name in { "Pets", "Hatch", "Stages", "Camp", "Codex", "Quests", "Shop", "Arena" } do
		openScreen(name)
		local clicked = 0
		for _, b in CM.buttons() do
			if not SKIP[CM.text(b)] and CM.visible(b) and clicked < 40 then
				clicked += 1
				CM.click(b, 0.3)
				if Screens.current() == "Battle" then
					finishBattle(name .. " fuzz battle", "Close")
				end
				for _ = 1, 5 do -- close any modals the click opened
					if not closeModal() then
						break
					end
				end
				if Screens.current() ~= name then
					openScreen(name)
				end
			end
		end
		noNewErrors("fuzz " .. name .. " (" .. clicked .. " buttons)")
	end
end

-- ---------------------------------------------------------------- failure scenarios (what a tester sees)
local function bootWorld(opts, before)
	local W = Mock.new(root, opts)
	if before then
		before(W)
	end
	local B = W.load("src/server/Boot.luau")
	W.spawn(function()
		B.run({ world = false })
	end)
	W.advance(0.1)
	return W
end

print("scenario: save service hangs (published place, Studio)")
do
	local W = bootWorld({ scheduler = true }, function(W)
		W.profileStore.hang = true
	end)
	local C2 = ClientMock.new(W, root, { userId = 3002, name = "Waiter" })
	C2.start()
	W.advance(10)
	check(
		C2.playerGui:FindFirstChild("VoxelPetsBoot") ~= nil,
		"loading screen stays up while waiting"
	)
	check(C2.byText("waiting for the save service") ~= nil, "loading screen says what it waits for")
	W.advance(3) -- diagnostics appear after 12 s
	check(C2.byText("save: waiting") ~= nil, "diagnostics show the save state")
	W.advance(13)
	check(
		C2.byText("Stuck here?") ~= nil or C2.playerGui:FindFirstChild("VoxelPetsUI") ~= nil,
		"hint or game after 20 s"
	)
	W.advance(5)
	check(
		C2.playerGui:FindFirstChild("VoxelPetsUI") ~= nil,
		"game starts after the Studio fallback"
	)
	check(C2.byText("TEST MODE") ~= nil, "fallback is flagged as test mode")
	check(#C2.errors == 0, "no client errors: " .. table.concat(C2.errors, " | "))
end

print("scenario: a server system failed to start")
do
	local W = bootWorld({ scheduler = true, placeId = 0 }, function(W)
		W.breakModule("src/server/Services/ArenaService.luau", "boom: arena exploded")
	end)
	local C3 = ClientMock.new(W, root, { userId = 3003, name = "Degraded" })
	C3.start()
	W.advance(2) -- the toast lives 3 s
	check(C3.playerGui:FindFirstChild("VoxelPetsUI") ~= nil, "game still starts")
	check(
		C3.byText("Some features are unavailable") ~= nil,
		"player is told some features are down"
	)
	W.advance(3)
	local S3 = C3.require("src/client/UI/ScreenManager.luau")
	C3.run(function()
		S3.open("Arena")
	end, 1)
	check(
		C3.byText("Unavailable right now") ~= nil,
		"broken feature explains itself instead of hanging"
	)
	check(#C3.errors == 0, "no client errors: " .. table.concat(C3.errors, " | "))
end

print(string.format("\n%d passed, %d failed", passes, failures))
if #CM.remoteIssues > 0 then
	print("remote payload issues:")
	for _, msg in CM.remoteIssues do
		print("  " .. msg)
	end
end
if VERBOSE then
	print("warnings:")
	for _, w in CM.warnings do
		print("  " .. w)
	end
end
if failures > 0 then
	process.exit(1)
end
