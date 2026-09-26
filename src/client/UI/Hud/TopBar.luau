--!nonstrict
-- Top-left currency strip: coins + gems always; "+" opens the other currencies (only those whose
-- feature is unlocked, so a new player is not shown five zeros). Top-right: settings gear.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Config.Formulas)
local Features = require(Shared.Config.Features)

local PixelIcons = require(script.Parent.Parent.PixelIcons)
local Settings = require(script.Parent.Settings)

local TopBar = {}

local PRIMARY = {
	{ id = "coins", icon = "coin" },
	{ id = "gems", icon = "gem" },
}
-- secondary currency -> feature that makes it relevant (nil = always relevant)
local SECONDARY = {
	{ id = "essence", label = "Essence", note = "evolve pets" },
	{ id = "shards", label = "Shards", note = "star up pets" },
	{ id = "tickets", label = "Tickets", note = "expedition entry", feature = "Expedition" },
	{ id = "marks", label = "Marks", note = "expedition talents", feature = "Expedition" },
	{ id = "medals", label = "Medals", note = "arena rewards", feature = "Arena" },
}
TopBar.KEYS = { "coins", "gems", "essence", "shards", "tickets", "marks", "medals", "stages" }

function TopBar.build(root, ctx)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State
	local bar = C.frame({
		Name = "Currencies",
		Size = UDim2.fromOffset(300, 32),
		Position = UDim2.fromOffset(10, 8),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.list(bar, 6, Enum.FillDirection.Horizontal)
	local labels = {}
	for i, c in PRIMARY do
		local pill = C.frame({
			Name = "Pill_" .. c.id,
			Size = UDim2.fromOffset(122, 32),
			BackgroundColor3 = Theme.Colors.panel,
			LayoutOrder = i,
			Parent = bar,
		})
		C.stroke(pill, Theme.Colors.border, 2)
		PixelIcons.new(c.icon, 20, { Position = UDim2.fromOffset(6, 6), Parent = pill })
		labels[c.id] = C.label({
			Size = UDim2.new(1, -34, 1, 0),
			Position = UDim2.fromOffset(32, 0),
			Text = "0",
			TextSize = 11,
			Parent = pill,
		})
	end
	local drop = C.panel({
		Name = "CurrencyDrop",
		Size = UDim2.fromOffset(250, 40),
		Position = UDim2.fromOffset(10, 46),
		Visible = false,
		ZIndex = 40,
		Parent = root,
	})
	local more
	more = C.button({
		Name = "MoreCurrencies",
		Size = UDim2.fromOffset(32, 32),
		Text = "+",
		TextSize = 14,
		BackgroundColor3 = Theme.Colors.panelLight,
		LayoutOrder = 10,
		Parent = bar,
	}, function()
		drop.Visible = not drop.Visible
		more.Text = if drop.Visible then "-" else "+"
	end)

	local rows = {}
	local function refresh()
		local p = State.profile
		if not p then
			return
		end
		for id, l in labels do
			l.Text = Formulas.formatNumber(p[id] or 0)
		end
		for _, r in rows do
			r:Destroy()
		end
		table.clear(rows)
		local y = 8
		for _, c in SECONDARY do
			if c.feature == nil or Features.isUnlocked(p, c.feature) then
				local row = C.frame({
					Size = UDim2.new(1, -16, 0, 24),
					Position = UDim2.fromOffset(8, y),
					BackgroundTransparency = 1,
					ZIndex = 41,
					Parent = drop,
				})
				C.frame({
					Size = UDim2.fromOffset(12, 12),
					Position = UDim2.fromOffset(2, 6),
					BackgroundColor3 = Theme.currencyColor(c.id),
					ZIndex = 42,
					Parent = row,
				})
				C.label({
					Size = UDim2.new(1, -24, 1, 0),
					Position = UDim2.fromOffset(22, 0),
					Text = string.format("%s  %s", c.label, Formulas.formatNumber(p[c.id] or 0)),
					TextSize = 9,
					ZIndex = 42,
					Parent = row,
				})
				C.label({
					Size = UDim2.new(1, -24, 1, 0),
					Position = UDim2.fromOffset(22, 0),
					Text = c.note,
					TextSize = 7,
					TextColor3 = Theme.Colors.textDim,
					TextXAlignment = Enum.TextXAlignment.Right,
					ZIndex = 42,
					Parent = row,
				})
				table.insert(rows, row)
				y += 26
			end
		end
		drop.Size = UDim2.fromOffset(250, y + 6)
	end
	State.onKeys(TopBar.KEYS, refresh)
	refresh()

	local gear = C.button({
		Name = "SettingsButton",
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -50, 0, 4),
		Text = "",
		BackgroundColor3 = Theme.Colors.panelLight,
		Parent = root,
	}, function()
		Settings.open(ctx)
	end)
	PixelIcons.new("gear", 30, { Position = UDim2.fromOffset(5, 5), Parent = gear })

	return { bar = bar, drop = drop, more = more, gear = gear, refresh = refresh }
end

return TopBar
