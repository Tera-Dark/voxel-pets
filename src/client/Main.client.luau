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
local Workspace = game:GetService("Workspace")

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
	core.Features = require(Shared.Config.Features)
	core.Tutorial = require(Client.UI.Tutorial)
	core.BattleFlow = require(Client.BattleFlow)
end, traceback)
if not coreOk then
	boot:set("connect", "fail", "game scripts failed to load")
	boot:problem(tostring(coreErr))
	warn("[Client] core modules failed: " .. tostring(coreErr))
	return
end
local StagesConfig, Net, State, Screens = core.StagesConfig, core.Net, core.State, core.Screens
local BattleStage, Companion = core.BattleStage, core.Companion
local Features, Tutorial, BattleFlow = core.Features, core.Tutorial, core.BattleFlow

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

-- Designed at 1280x720; UIScale keeps the layout proportional on phones and large monitors.
local ctx = {} -- shared UI context (declared before rescale(), which reads ctx.hud)
local uiScale = Instance.new("UIScale")
uiScale.Parent = gui
local function rescale()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end
	-- 0.75 floor keeps the pixel text readable on phones; screens fit themselves (ScreenManager)
	uiScale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.75, 1.3)
	if ctx and ctx.hud then
		ctx.hud.dock.relayout()
	end
	if Screens and Screens.refit then
		Screens.refit()
	end
end
step("ui scale", function()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end)

local host = C.frame({
	Name = "Screens",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = gui,
})

rescale()
-- Logical (pre-UIScale) size of the HUD canvas, for layout decisions (dock row, screen fit).
function ctx.canvasSize(): Vector2
	local size = host.AbsoluteSize
	local s = uiScale.Scale
	return Vector2.new(size.X / s, size.Y / s)
end
ctx.Net = Net
ctx.State = State
ctx.Screens = Screens
ctx.C = C
ctx.Theme = Theme
ctx.gui = gui
function ctx.toast(text, kind)
	C.toast(gui, tostring(text), kind)
end

-- Opens a HUD feature (feature ids = screen names) or explains how to unlock it.
function ctx.openFeature(id: string, arg)
	local feature = Features.ById[id]
	if feature and not Features.isUnlocked(State.profile, id) then
		ctx.toast(Features.requirement(id) .. " to unlock " .. feature.label, "info")
		return false
	end
	Screens.toggle(id, arg)
	return true
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

step("tutorial", function()
	Tutorial.start(ctx)
end)

-- Stations in the hub world
step("stations", function()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= player then
			return
		end
		local screen = prompt.Parent and prompt.Parent:GetAttribute("Screen")
		if type(screen) == "string" and Screens.current() ~= screen then
			ctx.openFeature(screen)
		end
	end)
end)

-- Locked stations say so locally (client-side only; the server world stays unchanged).
-- Runs in its own thread: waiting for the world must never hold up the rest of the UI.
task.spawn(step, "station labels", function()
	local stations = Workspace:WaitForChild("Hub", 10)
	stations = stations and stations:FindFirstChild("Stations")
	if not stations then
		return
	end
	local originals = {}
	local function refreshStations()
		for _, prompt in stations:GetDescendants() do
			if prompt:IsA("ProximityPrompt") then
				local screen = prompt.Parent and prompt.Parent:GetAttribute("Screen")
				originals[prompt] = originals[prompt] or { action = prompt.ActionText }
				local locked = type(screen) == "string"
					and Features.ById[screen] ~= nil
					and not Features.isUnlocked(State.profile, screen)
				prompt.ActionText = if locked
					then "Locked: " .. Features.requirement(screen)
					else originals[prompt].action
			end
		end
	end
	refreshStations()
	State.onKeys({ "stages", "stats" }, refreshStations)
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
step("battle playback", function()
	BattleFlow.start({
		ctx = ctx,
		Screens = Screens,
		BattleStage = BattleStage,
		Battle = ScreenModules.Battle,
		Stages = ScreenModules.Stages,
		StagesConfig = StagesConfig,
		Net = Net,
		State = State,
		Theme = Theme,
		step = step,
	})
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
		Size = UDim2.fromOffset(250, 18),
		Position = UDim2.new(1, -60, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = Theme.Colors.bad,
		Text = "TEST MODE: not saved",
		TextSize = 8,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 0, -- beneath open screens
		Parent = gui,
	})
end)

-- Build stamp in the bottom-right corner (tiny; lets any screenshot identify the build).
step("build label", function()
	C.label({
		Name = "BuildLabel",
		Size = UDim2.fromOffset(300, 12),
		Position = UDim2.new(1, -60, 0, 30),
		AnchorPoint = Vector2.new(1, 0),
		Text = BUILD_TEXT,
		TextSize = 7,
		TextTransparency = 0.35,
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 0, -- beneath open screens
		Parent = gui,
	})
end)

-- (Daily reward reminders are a "!" badge on Quests in the dock - no popup on join.)

if degraded then
	ctx.toast("Some features are unavailable right now", "bad")
end
print("[VoxelPets] client ready")
