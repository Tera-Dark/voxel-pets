--!nonstrict
-- Client entry point: builds the ScreenGui, waits for the profile, wires screens, stations,
-- battle playback and server events.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local StarterGui = game:GetService("StarterGui")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local StagesConfig = require(Shared.Config.Stages)

local Client = script.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Theme = require(Client.UI.PixelTheme)
local C = require(Client.UI.Components)
local Screens = require(Client.UI.ScreenManager)
local BattleStage = require(Client.World.BattleStage)
local Companion = require(Client.World.Companion)

local ScreenModules = {
	HUD = require(Client.UI.Screens.HUD),
	Battle = require(Client.UI.Screens.Battle),
	Pets = require(Client.UI.Screens.Pets),
	Hatch = require(Client.UI.Screens.Hatch),
	Stages = require(Client.UI.Screens.Stages),
	Camp = require(Client.UI.Screens.Camp),
	Expedition = require(Client.UI.Screens.Expedition),
	Arena = require(Client.UI.Screens.Arena),
	Codex = require(Client.UI.Screens.Codex),
	Quests = require(Client.UI.Screens.Quests),
	Shop = require(Client.UI.Screens.Shop),
	Prestige = require(Client.UI.Screens.Prestige),
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

-- ---------------------------------------------------------------- loading
local loading = C.label({
	Size = UDim2.fromScale(1, 1),
	Text = "Loading your pets...",
	TextSize = 16,
	BackgroundTransparency = 0,
	BackgroundColor3 = Theme.Colors.bg,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 100,
	Parent = gui,
})

Net.on("ProfileDelta", function(delta)
	State.apply(delta)
end)

-- The server replicates the full profile on load; ask for it too in case we joined late.
task.spawn(function()
	local ok, _, profile = Net.invoke("GetProfile")
	if ok and profile and not State.loaded then
		State.apply(profile)
	end
end)

while not State.loaded do
	task.wait(0.1)
end
loading:Destroy()

-- ---------------------------------------------------------------- screens
Screens.init(host, ctx)
for name, module in ScreenModules do
	if name ~= "HUD" then
		Screens.register(name, module)
	end
end
local hud = ScreenModules.HUD.build(host, ctx)
hud.ZIndex = 1

Screens.Opened:Connect(function(name)
	-- hide the HUD menu while a full-screen battle plays
	hud.Visible = name ~= "Battle"
end)

-- Stations in the hub world
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then
		return
	end
	local screen = prompt.Parent and prompt.Parent:GetAttribute("Screen")
	if type(screen) == "string" then
		Screens.open(screen)
	end
end)

-- ---------------------------------------------------------------- companion
local function refreshCompanion()
	local inst = State.teamPet()
	Companion.set(inst)
end
refreshCompanion()
State.onKeys({ "team", "pets" }, refreshCompanion)
player.CharacterAdded:Connect(function()
	task.wait(0.5)
	refreshCompanion()
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
	if payload.mode == "Stage" then
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

Net.on("BattleResult", function(payload)
	if type(payload) ~= "table" or not payload.teamA or not payload.teamB then
		return
	end
	local settings = State.profile.settings or {}
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
end)

-- ---------------------------------------------------------------- server events
Net.on("OfflineReport", function(report)
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
end)

-- Daily reminder
task.delay(3, function()
	local p = State.profile
	if p and p.stats and p.stats.lastDailyClaim ~= os.date("!%Y-%m-%d") then
		ctx.toast("Daily reward available - open Quests", "info")
	end
end)

print("[VoxelPets] client ready")
