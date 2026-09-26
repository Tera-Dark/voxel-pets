--!nonstrict
-- Client entry point.
--   1. Dev log + loading screen come up first (before anything that could fail).
--   2. Client modules are required under xpcall; a broken screen module becomes an error panel.
--   3. Handshake connect -> server -> save never waits silently: every stage shows progress, and
--      diagnostics (server boot state/errors, save state, last error) appear if it takes long.
--   4. The UI is wired in independent steps so one failing piece cannot take the others down.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Client = script.Parent
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Theme = require(Client.UI.PixelTheme)
local C = require(Client.UI.Components)
local DevConsole = require(Client.UI.DevConsole)
local BootScreen = require(Client.UI.BootScreen)

-- "v0.1.1 (f6220d8 2026-09-26)": visible on the loading screen and in the corner so every
-- screenshot shows which build is running.
local function buildText(): string
	local ok, info = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BuildInfo"))
	end)
	if ok and type(info) == "table" then
		return string.format("v%s (%s)", tostring(info.VERSION), tostring(info.BUILD))
	end
	return "v?"
end
local BUILD_TEXT = buildText()

DevConsole.start()
DevConsole.mount(playerGui)
local boot = BootScreen.new(playerGui, BUILD_TEXT)

local function traceback(err)
	return tostring(err) .. "\n" .. debug.traceback(nil, 2)
end

-- Runs one independent piece of client setup; failures go to the dev log instead of killing boot.
local function step(label: string, fn, ...)
	local ok, err = xpcall(fn, traceback, ...)
	if not ok then
		warn("[Client] " .. label .. " failed: " .. tostring(err))
	end
	return ok
end

local function diagnostics(): string
	local lines = {
		"server: "
			.. tostring(ReplicatedStorage:GetAttribute("VP_ServerState") or "no status yet")
			.. "   stage: "
			.. tostring(ReplicatedStorage:GetAttribute("VP_BootStage") or "-"),
		"save: " .. tostring(player:GetAttribute("VP_LoadState") or "no status yet"),
		"build: client " .. BUILD_TEXT .. " / server " .. tostring(
			ReplicatedStorage:GetAttribute("VP_ServerBuild") or "?"
		),
	}
	local errs = ReplicatedStorage:GetAttribute("VP_BootErrors")
	if type(errs) == "string" and errs ~= "" then
		table.insert(lines, "server problems:\n" .. errs)
	end
	local last = DevConsole.lastError()
	if last then
		table.insert(lines, "last error (" .. last.source .. "): " .. string.sub(last.text, 1, 300))
	end
	return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------- protected requires
local core = {}
local coreOk, coreErr = xpcall(function()
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	core.StagesConfig = require(Shared.Config.Stages)
	core.Net = require(Client.Net)
	core.State = require(Client.State)
	core.Screens = require(Client.UI.ScreenManager)
	core.BattleStage = require(Client.World.BattleStage)
	core.Companion = require(Client.World.Companion)
end, traceback)
if not coreOk then
	boot:set("connect", "fail", "game scripts failed to load")
	boot:problem(tostring(coreErr))
	warn("[Client] core modules failed: " .. tostring(coreErr))
	return
end
local StagesConfig, Net, State, Screens = core.StagesConfig, core.Net, core.State, core.Screens
local BattleStage, Companion = core.BattleStage, core.Companion

local SCREEN_NAMES = {
	"HUD",
	"Battle",
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
local ScreenModules = {}
for _, name in SCREEN_NAMES do
	local ok, mod = xpcall(function()
		return require(Client.UI.Screens[name])
	end, traceback)
	if ok then
		ScreenModules[name] = mod
	else
		warn("[Client] screen " .. name .. " failed to load: " .. tostring(mod))
		ScreenModules[name] = {
			build = function()
				error("screen module failed to load: " .. tostring(mod))
			end,
		}
	end
end

-- ---------------------------------------------------------------- handshake
-- 1) connect: the server creates the Remotes folder first thing during boot
boot:set("connect", "active")
while not Net.folder(1) do
	boot:tick()
	if boot:elapsedSeconds() > 10 then
		boot:set("connect", "active", "no answer from the server yet")
		boot:problem(diagnostics())
	end
end
boot:set("connect", "ok")
DevConsole.attachServer(Net)

-- 2) server services + 3) save
Net.on("ProfileDelta", function(delta)
	if type(delta) == "table" then
		State.apply(delta)
	end
end)
local asking, lastAsk = false, -math.huge
while not State.loaded do
	local serverState = ReplicatedStorage:GetAttribute("VP_ServerState")
	if serverState == "ready" then
		boot:set("server", "ok")
	elseif serverState == "degraded" then
		boot:set("server", "warn", "some systems failed")
	else
		boot:set("server", "active", ReplicatedStorage:GetAttribute("VP_BootStage"))
	end
	local loadState = player:GetAttribute("VP_LoadState")
	if loadState == "failed" then
		boot:set("save", "fail", "your save could not be loaded")
	elseif loadState == "waiting" then
		boot:set("save", "active", "waiting for the save service")
	else
		boot:set("save", "active")
	end
	-- Ask for the profile every few seconds: covers an early call answered "Loading" and any
	-- missed ProfileDelta. Net.invoke never blocks forever (timeout).
	if not asking and os.clock() - lastAsk > 3 then
		asking, lastAsk = true, os.clock()
		task.spawn(function()
			local ok, _, profile = Net.invoke("GetProfile")
			if ok and type(profile) == "table" and not State.loaded then
				State.apply(profile)
			end
			asking = false
		end)
	end
	if boot:elapsedSeconds() > 12 or serverState == "degraded" or loadState == "failed" then
		boot:problem(diagnostics())
	end
	boot:tick()
	task.wait(0.2)
end
local degraded = ReplicatedStorage:GetAttribute("VP_ServerState") == "degraded"
boot:set("server", if degraded then "warn" else "ok")
boot:set("save", "ok")
boot:destroy()

-- ---------------------------------------------------------------- gui root
local gui = Instance.new("ScreenGui")
gui.Name = "VoxelPetsUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local host = C.frame({
	Name = "Screens",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = gui,
})

local ctx = {}
ctx.Net = Net
ctx.State = State
ctx.Screens = Screens
ctx.C = C
ctx.Theme = Theme
ctx.gui = gui
function ctx.toast(text, kind)
	C.toast(gui, tostring(text), kind)
end

-- Generic pet picker modal used by Camp / Expedition. filter(uid) -> bool; onPick(uid)
function ctx.openPetPicker(title, filter, onPick)
	local content, close = C.modal(gui, title, UDim2.fromOffset(560, 420))
	local scroll = C.scroll({ Size = UDim2.new(1, 0, 1, -8), ZIndex = 52, Parent = content })
	C.list(scroll, 4)
	local any = false
	for i, row in State.petList() do
		if filter == nil or filter(row.uid) then
			any = true
			local busy = State.isBusy(row.uid)
			local text = string.format(
				"%s  Lv%d  %s %s  Power %d%s",
				State.petName(row.inst),
				row.inst.level,
				row.def.element,
				row.def.role,
				math.floor(row.power),
				busy and ("  [" .. busy .. "]") or ""
			)
			C.button({
				Size = UDim2.new(1, -8, 0, 30),
				Text = text,
				TextSize = 9,
				LayoutOrder = i,
				ZIndex = 53,
				BackgroundColor3 = Theme.Colors.panelLight,
				Parent = scroll,
			}, function()
				close()
				onPick(row.uid)
			end)
		end
	end
	if not any then
		C.label({
			Size = UDim2.new(1, 0, 0, 40),
			Text = "No available pets. Pets in your team or already working are busy.",
			TextSize = 9,
			ZIndex = 53,
			Parent = scroll,
		})
	end
end

-- ---------------------------------------------------------------- screens + HUD
step("screens", function()
	Screens.init(host, ctx)
	for name, module in ScreenModules do
		if name ~= "HUD" then
			Screens.register(name, module)
		end
	end
end)

local hud = nil
step("HUD", function()
	hud = ScreenModules.HUD.build(host, ctx)
	hud.ZIndex = 1
end)
Screens.Opened:Connect(function(name)
	-- hide the HUD menu while a full-screen battle plays
	if hud then
		hud.Visible = name ~= "Battle"
	end
end)

-- Stations in the hub world
step("stations", function()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= player then
			return
		end
		local screen = prompt.Parent and prompt.Parent:GetAttribute("Screen")
		if type(screen) == "string" then
			Screens.open(screen)
		end
	end)
end)

-- ---------------------------------------------------------------- companion
step("companion", function()
	local function refreshCompanion()
		Companion.set(State.teamPet())
	end
	refreshCompanion()
	State.onKeys({ "team", "pets" }, function()
		step("companion refresh", refreshCompanion)
	end)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		step("companion respawn", refreshCompanion)
	end)
end)

-- ---------------------------------------------------------------- battle playback
local Battle = ScreenModules.Battle
local Stages = ScreenModules.Stages

local function resultActions(payload)
	local actions = {}
	local function closeBattle()
		BattleStage.stop()
		Screens.close()
	end
	if payload.mode == "Stage" and Stages.current then
		local zone, stage = Stages.current()
		local won = payload.winner == "A"
		if won then
			table.insert(actions, {
				text = "Next",
				color = Theme.Colors.good,
				fn = function()
					BattleStage.stop()
					local nextStage, nextZone = stage + 1, zone
					if nextStage > StagesConfig.STAGES_PER_ZONE then
						nextStage, nextZone = 1, zone + 1
					end
					Screens.open("Stages", { zone = nextZone, stage = nextStage })
				end,
			})
		end
		table.insert(actions, {
			text = won and "Again" or "Retry",
			color = Theme.Colors.info,
			fn = function()
				local ok, err = Net.invoke("StartStage", zone, stage)
				if not ok then
					ctx.toast(err, "bad")
					closeBattle()
				end
			end,
		})
		table.insert(actions, {
			text = "Stages",
			color = Theme.Colors.panelLight,
			fn = function()
				BattleStage.stop()
				Screens.open("Stages", { zone = zone, stage = stage })
			end,
		})
	elseif payload.mode == "Arena" then
		table.insert(actions, {
			text = "Arena",
			color = Theme.Colors.info,
			fn = function()
				BattleStage.stop()
				Screens.open("Arena")
			end,
		})
	elseif payload.mode == "Expedition" then
		table.insert(actions, {
			text = "Map",
			color = Theme.Colors.info,
			fn = function()
				BattleStage.stop()
				Screens.open("Expedition")
			end,
		})
	end
	table.insert(actions, { text = "Close", color = Theme.Colors.panelLight, fn = closeBattle })
	return actions
end

local function playBattle(payload)
	if type(payload) ~= "table" or not payload.teamA or not payload.teamB then
		return
	end
	local settings = (State.profile and State.profile.settings) or {}
	Screens.open("Battle")
	local battleUi = nil
	local ctl = BattleStage.play(payload, {
		speed = settings.battleSpeed or 1,
		onHp = function(uid, hp, shield)
			if battleUi then
				battleUi.onHp(uid, hp, shield)
			end
		end,
		onLog = function(text, kind)
			if battleUi then
				battleUi.onLog(text, kind)
			end
		end,
		onFinished = function()
			if battleUi then
				battleUi.showResult()
			end
		end,
	})
	battleUi = Battle.show(ctx, payload, ctl, resultActions(payload))
	if settings.autoSkip then
		task.defer(function()
			ctl.skip()
		end)
	end
end

step("battle playback", function()
	Net.on("BattleResult", function(payload)
		if not step("battle", playBattle, payload) then
			BattleStage.stop()
			Screens.close()
			ctx.toast("The battle replay failed to load", "bad")
		end
	end)
end)

-- ---------------------------------------------------------------- server events
local function showOfflineReport(report)
	if type(report) ~= "table" then
		return
	end
	local hours = report.seconds / 3600
	local content, close = C.modal(gui, "Welcome back!", UDim2.fromOffset(460, 220))
	local text = string.format(
		"Your camp worked for %s while you were away.\n\nPending: +%d coins, +%d tickets%s\n\nVisit the Camp to collect.",
		hours >= 1 and string.format("%.1f hours", hours)
			or string.format("%d minutes", math.floor(report.seconds / 60)),
		report.coins or 0,
		report.tickets or 0,
		report.capped and "\n(Offline cap reached - VIP extends it to 12h)" or ""
	)
	C.label({
		Size = UDim2.new(1, 0, 1, -50),
		Text = text,
		TextSize = 10,
		ZIndex = 53,
		Parent = content,
	})
	C.button({
		Size = UDim2.fromOffset(160, 32),
		Position = UDim2.new(0.5, -80, 1, -40),
		Text = "Go to Camp",
		ZIndex = 53,
		BackgroundColor3 = Theme.Colors.good,
		Parent = content,
	}, function()
		close()
		Screens.open("Camp")
	end)
end

step("offline report", function()
	Net.on("OfflineReport", function(report)
		step("offline report popup", showOfflineReport, report)
	end)
end)

-- Studio without DataStore access: make it obvious that progress is not saved.
step("save mode banner", function()
	if player:GetAttribute("VP_SaveMode") ~= "offline" then
		return
	end
	C.label({
		Name = "TestModeBanner",
		Size = UDim2.fromOffset(330, 20),
		Position = UDim2.new(0.5, 0, 0, 2),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = Theme.Colors.bad,
		Text = "TEST MODE - progress is not saved",
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 80,
		Parent = gui,
	})
end)

-- Build stamp in the bottom-right corner (tiny; lets any screenshot identify the build).
step("build label", function()
	C.label({
		Name = "BuildLabel",
		Size = UDim2.fromOffset(260, 14),
		Position = UDim2.new(1, -266, 1, -16),
		Text = BUILD_TEXT,
		TextSize = 7,
		TextTransparency = 0.35,
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 5,
		Parent = gui,
	})
end)

-- Daily reminder
task.delay(3, function()
	local p = State.profile
	if p and p.stats and p.stats.lastDailyClaim ~= os.date("!%Y-%m-%d") then
		ctx.toast("Daily reward available - open Quests", "info")
	end
end)

if degraded then
	ctx.toast("Some features are unavailable right now", "bad")
end
print("[VoxelPets] client ready")
