--!nonstrict
-- On-screen developer log: client errors/warnings (ScriptContext / LogService) + server problems
-- (DevLog remote). Visible only to developers (Studio, or the place owner: the server sets the
-- player attribute VP_Dev). A red "ERR n" / yellow "WARN n" badge in the bottom-left opens a
-- scrollable log, so a tester can report any problem with one screenshot - no Output window.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")
local ScriptContext = game:GetService("ScriptContext")

local Theme = require(script.Parent.PixelTheme)
local C = require(script.Parent.Components)

local DevConsole = {}

local MAX_ENTRIES = 80
local MAX_ROWS = 40
local entries = {}
local counts = { error = 0, warn = 0 }
local changed = Instance.new("BindableEvent")
DevConsole.Changed = changed.Event

local started = false
local ui = nil -- { gui, badge, panel, list }

function DevConsole.isDev(): boolean
	if RunService:IsStudio() then
		return true
	end
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("VP_Dev") == true
end

local function trim(text, n)
	text = tostring(text)
	if #text > n then
		return string.sub(text, 1, n) .. " ..."
	end
	return text
end

-- source: "client" | "server"; kind: "error" | "warn"
function DevConsole.push(source: string, kind: string, text)
	text = trim(text, 900)
	local last = entries[#entries]
	if last and last.text == text and last.source == source then
		last.count += 1
		last.t = os.time()
	else
		table.insert(
			entries,
			{ t = os.time(), source = source, kind = kind, text = text, count = 1 }
		)
		if #entries > MAX_ENTRIES then
			table.remove(entries, 1)
		end
	end
	counts[kind] = (counts[kind] or 0) + 1
	changed:Fire()
end

function DevConsole.lastError()
	for i = #entries, 1, -1 do
		if entries[i].kind == "error" then
			return entries[i]
		end
	end
	return nil
end

function DevConsole.counts()
	return counts.error, counts.warn
end

-- Starts capturing client-side problems. Call as early as possible.
function DevConsole.start()
	if started then
		return
	end
	started = true
	ScriptContext.Error:Connect(function(message, trace)
		local text = tostring(message)
		if type(trace) == "string" and trace ~= "" then
			text ..= "\n" .. trace
		end
		DevConsole.push("client", "error", text)
	end)
	LogService.MessageOut:Connect(function(message, messageType)
		if messageType == Enum.MessageType.MessageWarning then
			DevConsole.push("client", "warn", message)
		end
	end)
end

-- Server problems forwarded by Boot (developer clients only).
function DevConsole.attachServer(Net)
	Net.on("DevLog", function(list)
		if type(list) ~= "table" then
			return
		end
		for _, e in list do
			if type(e) == "table" and type(e.text) == "string" then
				DevConsole.push("server", if e.kind == "error" then "error" else "warn", e.text)
			end
		end
	end)
end

-- ---------------------------------------------------------------- UI
local function refresh()
	if not ui then
		return
	end
	local nErr, nWarn = counts.error, counts.warn
	ui.badge.Visible = nErr + nWarn > 0
	if nErr > 0 then
		ui.badge.Text = "ERR " .. nErr
		ui.badge:SetAttribute("BaseColor", Theme.Colors.bad)
	else
		ui.badge.Text = "WARN " .. nWarn
		ui.badge:SetAttribute("BaseColor", Theme.Colors.panelLight)
	end
	if not ui.panel.Visible then
		return
	end
	for _, child in ui.list:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local shown = 0
	for i = #entries, 1, -1 do
		local e = entries[i]
		shown += 1
		if shown > MAX_ROWS then
			break
		end
		C.label({
			Size = UDim2.new(1, -8, 0, 16),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = string.format(
				"[%s] %s %s%s\n%s",
				os.date("%H:%M:%S", e.t),
				string.upper(e.source),
				string.upper(e.kind),
				if e.count > 1 then "  x" .. e.count else "",
				e.text
			),
			TextSize = 13,
			FontFace = Theme.monoFont(),
			TextColor3 = if e.kind == "error" then Theme.Colors.bad else Theme.Colors.accent,
			LayoutOrder = shown,
			Parent = ui.list,
		})
	end
end

-- Creates the badge + panel (developers only; waits for VP_Dev in live servers).
function DevConsole.mount(playerGui)
	if ui then
		return
	end
	if not DevConsole.isDev() then
		local player = Players.LocalPlayer
		local conn
		conn = player:GetAttributeChangedSignal("VP_Dev"):Connect(function()
			if DevConsole.isDev() then
				conn:Disconnect()
				DevConsole.mount(playerGui)
			end
		end)
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "VoxelPetsDevLog"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 950
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local panel = C.panel({
		Size = UDim2.fromScale(0.62, 0.6),
		Position = UDim2.new(0, 8, 1, -42),
		AnchorPoint = Vector2.new(0, 1),
		Visible = false,
		Parent = gui,
	}, "Developer log")
	local list = C.scroll({
		Size = UDim2.new(1, -12, 1, -76),
		Position = UDim2.fromOffset(6, 36),
		Parent = panel,
	})
	C.list(list, 6)
	C.label({
		Size = UDim2.new(1, -250, 0, 30),
		Position = UDim2.new(0, 8, 1, -36),
		Text = "Screenshot this panel to report a problem.",
		TextSize = 9,
		TextColor3 = Theme.Colors.textDim,
		Parent = panel,
	})
	C.button({
		Size = UDim2.fromOffset(100, 28),
		Position = UDim2.new(1, -218, 1, -34),
		Text = "Clear",
		TextSize = 10,
		BackgroundColor3 = Theme.Colors.panelLight,
		Parent = panel,
	}, function()
		table.clear(entries)
		counts.error, counts.warn = 0, 0
		changed:Fire()
	end)
	C.button({
		Size = UDim2.fromOffset(100, 28),
		Position = UDim2.new(1, -110, 1, -34),
		Text = "Close",
		TextSize = 10,
		BackgroundColor3 = Theme.Colors.bad,
		Parent = panel,
	}, function()
		panel.Visible = false
	end)
	local badge = C.button({
		Size = UDim2.fromOffset(96, 28),
		Position = UDim2.new(0, 8, 1, -36),
		Text = "LOG",
		TextSize = 10,
		BackgroundColor3 = Theme.Colors.bad,
		Visible = false,
		Parent = gui,
	}, function()
		panel.Visible = not panel.Visible
		refresh()
	end)
	ui = { gui = gui, badge = badge, panel = panel, list = list }
	changed.Event:Connect(refresh)
	refresh()
end

return DevConsole
