--!nonstrict
-- Battle playback overlay: HP bars, event log, speed/skip, result panel. Driven by BattleController.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Formulas = require(Shared.Config.Formulas)

local Battle = {}

local ui = nil
local ctxTheme = nil -- Theme.Colors, set on first show

function Battle.build(host, ctx)
	local C, Theme = ctx.C, ctx.Theme
	local root = C.frame({
		Name = "Battle",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = host,
	})

	local function sidePanel(anchorX, name)
		local panel = C.panel({
			Size = UDim2.fromOffset(340, 92),
			Position = UDim2.new(anchorX, anchorX == 0 and 20 or -20, 0, 70),
			AnchorPoint = Vector2.new(anchorX, 0),
			ZIndex = 21,
			Parent = root,
		})
		local title = C.label({
			Size = UDim2.new(1, -16, 0, 22),
			Position = UDim2.fromOffset(8, 6),
			Text = name,
			TextSize = 12,
			ZIndex = 22,
			Parent = panel,
		})
		local sub = C.label({
			Size = UDim2.new(1, -16, 0, 16),
			Position = UDim2.fromOffset(8, 28),
			Text = "",
			TextSize = 9,
			TextColor3 = Theme.Colors.textDim,
			ZIndex = 22,
			Parent = panel,
		})
		local hp = C.bar({
			Size = UDim2.new(1, -16, 0, 18),
			Position = UDim2.fromOffset(8, 48),
			ZIndex = 22,
			Parent = panel,
		})
		hp.fill.ZIndex = 22
		hp.text.ZIndex = 23
		local shield = C.bar({
			Size = UDim2.new(1, -16, 0, 8),
			Position = UDim2.fromOffset(8, 70),
			ZIndex = 22,
			Parent = panel,
		}, Theme.Colors.shield, Theme.Colors.panelLight)
		shield.fill.ZIndex = 22
		return { panel = panel, title = title, sub = sub, hp = hp, shield = shield }
	end
	local left = sidePanel(0, "You")
	local right = sidePanel(1, "Enemy")

	local controls = C.frame({
		Size = UDim2.fromOffset(300, 36),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = root,
	})
	C.list(controls, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	local speedButtons = {}
	for _, s in { 1, 2, 3 } do
		speedButtons[s] = C.button({
			Size = UDim2.fromOffset(52, 32),
			Text = s .. "x",
			ZIndex = 22,
			BackgroundColor3 = Theme.Colors.panelLight,
			Parent = controls,
		}, function()
			ui.setSpeed(s)
		end)
	end
	local skipBtn = C.button({
		Size = UDim2.fromOffset(90, 32),
		Text = "SKIP >>",
		ZIndex = 22,
		BackgroundColor3 = Theme.Colors.bad,
		Parent = controls,
	}, function()
		ui.skip()
	end)

	local log = C.scroll({
		Size = UDim2.fromOffset(360, 110),
		Position = UDim2.new(0.5, 0, 1, -140),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 21,
		BackgroundTransparency = 0.4,
		BackgroundColor3 = Theme.Colors.bg,
		Parent = root,
	})
	C.list(log, 2)
	C.padding(log, 4)

	local result = C.panel({
		Size = UDim2.fromOffset(420, 250),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 30,
		Visible = false,
		Parent = root,
	}, "Result")
	result.Title.ZIndex = 31
	local resultTitle = C.label({
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 40),
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 31,
		Parent = result,
	})
	local resultBody = C.label({
		Size = UDim2.new(1, -20, 0, 100),
		Position = UDim2.fromOffset(10, 84),
		TextSize = 11,
		ZIndex = 31,
		Parent = result,
	})
	local resultButtons = C.frame({
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.new(0, 10, 1, -46),
		BackgroundTransparency = 1,
		ZIndex = 31,
		Parent = result,
	})
	C.list(resultButtons, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)

	ui = {
		root = root,
		left = left,
		right = right,
		log = log,
		result = result,
		resultTitle = resultTitle,
		resultBody = resultBody,
		resultButtons = resultButtons,
		speedButtons = speedButtons,
		skipBtn = skipBtn,
		setSpeed = function() end,
		skip = function() end,
	}
	return root
end

local function paintSpeed(speed)
	for s, b in ui.speedButtons do
		b:SetAttribute("BaseColor", s == speed and ctxTheme.good or ctxTheme.panelLight)
	end
end

-- Called by BattleController when a payload arrives.
-- ctl: BattleStage controller; actions: list of { text, color, fn } for the result panel.
function Battle.show(ctx, payload, ctl, actions)
	ctxTheme = ctx.Theme.Colors
	local C = ctx.C
	local a, b = payload.teamA[1], payload.teamB[1]
	ui.left.title.Text = a.name .. "  Lv" .. a.level
	ui.left.sub.Text = string.format(
		"%s %s  ATK %d DEF %d SPD %d",
		Pets[a.petId].element,
		Pets[a.petId].role,
		a.atk,
		a.def,
		a.spd
	)
	ui.right.title.Text = b.name .. "  Lv" .. b.level
	ui.right.sub.Text = string.format(
		"%s %s  ATK %d DEF %d SPD %d",
		Pets[b.petId].element,
		Pets[b.petId].role,
		b.atk,
		b.def,
		b.spd
	)
	local maxHp = {}
	for _, c in payload.teamA do
		maxHp[c.uid] = c.maxHp
	end
	for _, c in payload.teamB do
		maxHp[c.uid] = c.maxHp
	end
	ui.left.hp.set(
		a.hp / a.maxHp,
		Formulas.formatNumber(a.hp) .. " / " .. Formulas.formatNumber(a.maxHp)
	)
	ui.right.hp.set(
		b.hp / b.maxHp,
		Formulas.formatNumber(b.hp) .. " / " .. Formulas.formatNumber(b.maxHp)
	)
	ui.left.shield.set(0)
	ui.right.shield.set(0)
	for _, child in ui.log:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	ui.result.Visible = false
	for _, child in ui.resultButtons:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	ui.onHp = function(uid, hp, shield)
		local side = uid:sub(1, 1) == "A" and ui.left or ui.right
		side.hp.set(
			hp / maxHp[uid],
			Formulas.formatNumber(hp) .. " / " .. Formulas.formatNumber(maxHp[uid]),
			true
		)
		side.shield.set(shield / maxHp[uid])
	end
	ui.onLog = function(text, kind)
		local color = kind == "bad" and ctxTheme.bad
			or (
				kind == "good" and ctxTheme.good
				or (kind == "skill" and ctxTheme.accent or ctxTheme.text)
			)
		C.label({
			Size = UDim2.new(1, 0, 0, 14),
			Text = text,
			TextSize = 9,
			TextColor3 = color,
			ZIndex = 22,
			Parent = ui.log,
		})
		ui.log.CanvasPosition = Vector2.new(0, 1e6)
	end
	ui.setSpeed = function(s)
		ctl.setSpeed(s)
		paintSpeed(s)
		ctx.State.profile.settings.battleSpeed = s
		ctx.Net.invoke("SetSetting", "battleSpeed", s)
	end
	ui.skip = function()
		ctl.skip()
	end
	paintSpeed(ctl.speed)

	ui.showResult = function()
		local won = payload.winner == "A"
		ui.resultTitle.Text = won and "VICTORY" or (payload.winner == "Draw" and "DRAW" or "DEFEAT")
		ui.resultTitle.TextColor3 = won and ctxTheme.good or ctxTheme.bad
		local lines = {}
		local r = payload.rewards or {}
		if payload.mode == "Stage" then
			if r.stars and r.stars > 0 then
				table.insert(
					lines,
					"Stars: " .. string.rep("*", r.stars) .. string.rep("-", 3 - r.stars)
				)
			end
			table.insert(lines, string.format("Coins +%d   XP +%d", r.coins or 0, r.xp or 0))
			if (r.gems or 0) > 0 then
				table.insert(lines, string.format("First clear! Gems +%d", r.gems))
			end
			if (r.essence or 0) > 0 then
				table.insert(lines, string.format("Essence +%d", r.essence))
			end
		elseif payload.mode == "Arena" then
			table.insert(
				lines,
				string.format(
					"Rating %+d   Medals +%d   Coins +%d",
					r.ratingDelta or 0,
					r.medals or 0,
					r.coins or 0
				)
			)
		elseif payload.mode == "Expedition" then
			table.insert(
				lines,
				won and "Pick your relic on the map." or "The expedition ends here."
			)
		end
		table.insert(
			lines,
			string.format(
				"Duration %.1fs%s",
				payload.duration,
				payload.timedOut and " (timeout)" or ""
			)
		)
		ui.resultBody.Text = table.concat(lines, "\n")
		for i, action in actions do
			local btn = C.button({
				Size = UDim2.fromOffset(120, 36),
				Text = action.text,
				BackgroundColor3 = action.color or ctxTheme.info,
				ZIndex = 32,
				LayoutOrder = i,
				Parent = ui.resultButtons,
			}, action.fn)
			btn.ZIndex = 32
		end
		ui.result.Visible = true
	end
	return ui
end

function Battle.onOpen() end

return Battle
