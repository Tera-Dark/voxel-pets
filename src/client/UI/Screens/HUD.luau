--!nonstrict
-- Always-visible HUD: currencies (top), menu buttons (left), announcement ticker, settings.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Config.Formulas)
local Pets = require(Shared.Config.Pets)

local HUD = {}

local CURRENCIES = { "coins", "gems", "essence", "shards", "marks", "tickets", "medals" }
local MENU = {
	{ "Pets", "Pets" },
	{ "Battle", "Stages" },
	{ "Hatch", "Hatch" },
	{ "Camp", "Camp" },
	{ "Expedition", "Expedition" },
	{ "Arena", "Arena" },
	{ "Codex", "Codex" },
	{ "Quests", "Quests" },
	{ "Shop", "Shop" },
	{ "Prestige", "Prestige" },
}

function HUD.build(host, ctx)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State
	local root = C.frame({
		Name = "HUD",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = host,
	})

	-- top bar
	local top = C.frame({
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.2,
		Parent = root,
	})
	local row = C.frame({
		Size = UDim2.new(1, -140, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		BackgroundTransparency = 1,
		Parent = top,
	})
	C.list(row, 6, Enum.FillDirection.Horizontal)
	row.UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	local labels = {}
	for i, currency in CURRENCIES do
		local _, l = C.currency(row, currency, "0", i)
		labels[currency] = l
	end
	local function refreshCurrencies()
		local p = State.profile
		if not p then
			return
		end
		for _, currency in CURRENCIES do
			labels[currency].Text = Formulas.formatNumber(p[currency] or 0)
		end
	end
	State.onKeys(CURRENCIES, refreshCurrencies)

	-- settings + player name (top right)
	local settingsBtn = C.button({
		Size = UDim2.fromOffset(110, 28),
		Position = UDim2.new(1, -118, 0, 6),
		Text = "Settings",
		BackgroundColor3 = Theme.Colors.panelLight,
		Parent = top,
	}, function()
		HUD.openSettings(ctx)
	end)
	local _ = settingsBtn

	-- left menu
	local menu = C.frame({
		Size = UDim2.fromOffset(120, 400),
		Position = UDim2.fromOffset(8, 52),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.list(menu, 4)
	for i, entry in MENU do
		C.button({
			Size = UDim2.new(1, 0, 0, 30),
			Text = entry[1],
			LayoutOrder = i,
			BackgroundColor3 = Theme.Colors.panelLight,
			TextSize = 11,
			Parent = menu,
		}, function()
			ctx.Screens.toggle(entry[2])
		end)
	end

	-- big "Battle" call to action bottom right
	C.button({
		Size = UDim2.fromOffset(160, 44),
		Position = UDim2.new(1, -172, 1, -56),
		Text = "BATTLE  >",
		BackgroundColor3 = Theme.Colors.bad,
		TextSize = 14,
		Parent = root,
	}, function()
		ctx.Screens.open("Stages")
	end)

	-- announcement ticker
	local ticker = C.label({
		Size = UDim2.fromOffset(600, 24),
		Position = UDim2.new(0.5, 0, 0, 46),
		AnchorPoint = Vector2.new(0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.accent,
		TextStrokeTransparency = 0,
		Text = "",
		Parent = root,
	})
	local queue = {}
	local showing = false
	local function pump()
		if showing or #queue == 0 then
			return
		end
		showing = true
		local item = table.remove(queue, 1)
		ticker.Text = item.text
		ticker.TextColor3 = Theme.Rarity[item.kind] or Theme.Colors.accent
		task.delay(5, function()
			ticker.Text = ""
			showing = false
			pump()
		end)
	end
	ctx.Net.on("Announcement", function(text, kind)
		if #queue < 5 then
			table.insert(queue, { text = text, kind = kind })
		end
		pump()
	end)
	ctx.Net.on("Toast", function(text, kind)
		ctx.toast(text, kind)
	end)

	-- active pet chip (bottom left)
	local chip = C.panel({
		Size = UDim2.fromOffset(240, 54),
		Position = UDim2.new(0, 8, 1, -62),
		Parent = root,
	})
	local chipName = C.label({
		Size = UDim2.new(1, -12, 0, 20),
		Position = UDim2.fromOffset(8, 6),
		Text = "",
		TextSize = 11,
		Parent = chip,
	})
	local chipInfo = C.label({
		Size = UDim2.new(1, -12, 0, 20),
		Position = UDim2.fromOffset(8, 28),
		Text = "",
		TextSize = 10,
		TextColor3 = Theme.Colors.textDim,
		Parent = chip,
	})
	local function refreshChip()
		local inst = State.teamPet()
		if inst then
			chipName.Text = State.petName(inst) .. "  Lv" .. inst.level
			chipInfo.Text = string.format(
				"%s %s  Power %s",
				Pets[inst.petId].element,
				Pets[inst.petId].rarity,
				Formulas.formatNumber(
					Formulas.power(Formulas.finalStats(Pets[inst.petId], inst, State.globalMult()))
				)
			)
		else
			chipName.Text = "No active pet"
			chipInfo.Text = ""
		end
	end
	State.onKeys({ "team", "pets", "codex", "prestige" }, refreshChip)
	chip.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			ctx.Screens.open("Pets")
		end
	end)

	refreshCurrencies()
	refreshChip()
	return root
end

function HUD.openSettings(ctx)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State
	local content = C.modal(ctx.gui, "Settings", UDim2.fromOffset(360, 220))
	C.list(content, 8)
	local settings = State.profile.settings
	C.label({ Size = UDim2.new(1, 0, 0, 20), Text = "Battle speed", ZIndex = 53, Parent = content })
	local speeds = C.frame({
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		ZIndex = 53,
		Parent = content,
	})
	C.list(speeds, 6, Enum.FillDirection.Horizontal)
	local speedButtons = {}
	local function paint()
		for s, b in speedButtons do
			b:SetAttribute(
				"BaseColor",
				s == settings.battleSpeed and Theme.Colors.good or Theme.Colors.panelLight
			)
		end
	end
	for _, s in { 1, 2, 3 } do
		speedButtons[s] = C.button(
			{ Size = UDim2.fromOffset(70, 32), Text = s .. "x", ZIndex = 54, Parent = speeds },
			function()
				settings.battleSpeed = s
				ctx.Net.invoke("SetSetting", "battleSpeed", s)
				paint()
			end
		)
	end
	paint()
	local skipBtn
	skipBtn = C.button({
		Size = UDim2.new(1, 0, 0, 32),
		Text = "Auto-skip battles: " .. (settings.autoSkip and "ON" or "OFF"),
		ZIndex = 54,
		BackgroundColor3 = Theme.Colors.panelLight,
		Parent = content,
	}, function()
		settings.autoSkip = not settings.autoSkip
		ctx.Net.invoke("SetSetting", "autoSkip", settings.autoSkip)
		skipBtn.Text = "Auto-skip battles: " .. (settings.autoSkip and "ON" or "OFF")
	end)
	C.label({
		Size = UDim2.new(1, 0, 0, 40),
		Text = "Combat is fully automatic. Your choices are made before the fight: team, relics, talents.",
		TextSize = 10,
		TextColor3 = Theme.Colors.textDim,
		ZIndex = 53,
		Parent = content,
	})
end

return HUD
