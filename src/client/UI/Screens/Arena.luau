--!nonstrict
-- Async PvP: three opponent snapshots (players or bots), Elo rating, leaderboard.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Rarities = require(Shared.Config.Rarities)
local Formulas = require(Shared.Config.Formulas)

local Screen = {}
local ui = {}
local offer = nil

local function clear(frame)
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function render(ctx)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State
	clear(ui.list)
	local p = State.profile
	local mine = State.teamPet()
	ui.header.Text = string.format(
		"Rating %d   W %d / L %d   Medals %d   Your pet: %s",
		p.arena.rating,
		p.arena.wins,
		p.arena.losses,
		p.medals or 0,
		mine
				and string.format(
					"%s Lv%d (Power %s)",
					State.petName(mine),
					mine.level,
					Formulas.formatNumber(State.power(mine))
				)
			or "none"
	)
	if not offer then
		return
	end
	for i, o in offer.opponents do
		local def = Pets[o.petId]
		local card =
			C.panel({ Size = UDim2.fromOffset(250, 170), LayoutOrder = i, Parent = ui.list })
		C.label({
			Size = UDim2.new(1, -12, 0, 18),
			Position = UDim2.fromOffset(6, 6),
			Text = o.name .. (o.bot and "  [BOT]" or ""),
			TextSize = 10,
			TextColor3 = o.bot and Theme.Colors.textDim or Theme.Colors.accent,
			Parent = card,
		})
		C.label({
			Size = UDim2.new(1, -12, 0, 16),
			Position = UDim2.fromOffset(6, 28),
			Text = string.format("Rating %d   Power %s", o.rating, Formulas.formatNumber(o.power)),
			TextSize = 8,
			Parent = card,
		})
		local variant = Rarities.VariantDisplay[o.variant] or ""
		C.label({
			Size = UDim2.new(1, -12, 0, 30),
			Position = UDim2.fromOffset(6, 48),
			Text = string.format(
				"%s%s  Lv%d\n%s %s",
				variant ~= "" and (variant .. " ") or "",
				def.displayName,
				o.level,
				def.element,
				def.role
			),
			TextSize = 8,
			TextColor3 = Theme.Rarity[def.rarity],
			Parent = card,
		})
		local delta = o.rating - p.arena.rating
		local hint = delta > 60 and "Hard  (+more rating)"
			or (delta < -60 and "Easy  (+less rating)" or "Even match")
		C.label({
			Size = UDim2.new(1, -12, 0, 16),
			Position = UDim2.fromOffset(6, 84),
			Text = hint,
			TextSize = 8,
			TextColor3 = Theme.Colors.textDim,
			Parent = card,
		})
		local fight = C.button({
			Size = UDim2.new(1, -12, 0, 30),
			Position = UDim2.new(0, 6, 1, -36),
			Text = "FIGHT",
			TextSize = 11,
			BackgroundColor3 = Theme.Colors.bad,
			Parent = card,
		}, function()
			local ok, err = ctx.Net.invoke("ArenaFight", i)
			if not ok then
				ctx.toast(err, "bad")
			end
			-- BattleResult event drives the playback; refresh offers afterwards
			offer = nil
			render(ctx)
		end)
		C.setEnabled(fight, mine ~= nil)
	end
end

local function fetchOffers(ctx)
	local ok, err, v = ctx.Net.invoke("ArenaGetOpponents")
	if ok then
		offer = v
	else
		offer = nil
		ctx.toast(err, "bad")
	end
	render(ctx)
end

local function fetchBoard(ctx)
	local ok, _, board = ctx.Net.invoke("ArenaLeaderboard")
	local lines = { "TOP RATINGS" }
	if ok and board and #board > 0 then
		for _, row in board do
			table.insert(
				lines,
				string.format(
					"%2d. %-14s %5d  (P %s)",
					row.rank,
					string.sub(row.name, 1, 14),
					row.rating,
					Formulas.formatNumber(row.power)
				)
			)
		end
	else
		table.insert(lines, "(no entries yet - fight to publish your rating)")
	end
	ui.board.Text = table.concat(lines, "\n")
end

function Screen.build(host, ctx)
	Screen.ctx = ctx
	local C, Theme = ctx.C, ctx.Theme
	local root = C.panel({
		Name = "Arena",
		Size = UDim2.fromOffset(860, 440),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = host,
	}, "Arena (async PvP)")
	ui.header = C.label({
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 36),
		TextSize = 9,
		TextColor3 = Theme.Colors.textDim,
		Parent = root,
	})
	ui.list = C.frame({
		Size = UDim2.fromOffset(780, 180),
		Position = UDim2.fromOffset(8, 62),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.list(ui.list, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	C.button({
		Size = UDim2.fromOffset(200, 28),
		Position = UDim2.fromOffset(8, 250),
		Text = "New opponents",
		TextSize = 9,
		BackgroundColor3 = Theme.Colors.info,
		Parent = root,
	}, function()
		fetchOffers(ctx)
	end)
	C.label({
		Size = UDim2.fromOffset(560, 40),
		Position = UDim2.fromOffset(220, 246),
		Text = "Your active team pet fights a snapshot of another player's pet. Win: +10 medals. Loss: +2 medals. Rating uses Elo; opponents are matched by power.",
		TextSize = 8,
		TextColor3 = Theme.Colors.textDim,
		Parent = root,
	})
	ui.board = C.label({
		Size = UDim2.new(1, -16, 0, 130),
		Position = UDim2.fromOffset(8, 296),
		TextSize = 8,
		Parent = root,
	})
	C.button({
		Size = UDim2.fromOffset(28, 24),
		Position = UDim2.new(1, -31, 0, 3),
		Text = "X",
		BackgroundColor3 = Theme.Colors.bad,
		Parent = root,
	}, function()
		ctx.Screens.close()
	end)
	ctx.State.onKeys({ "arena", "medals", "team" }, function()
		if root.Visible then
			render(ctx)
		end
	end)
	return root
end

function Screen.onOpen()
	local ctx = Screen.ctx
	render(ctx)
	fetchOffers(ctx)
	fetchBoard(ctx)
end

return Screen
