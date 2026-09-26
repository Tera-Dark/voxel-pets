--!nonstrict
-- Hatchery: egg cards, numeric odds disclosure ("Details") before any purchase, hatch x1 / x3.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Eggs = require(Shared.Config.Eggs)
local Rarities = require(Shared.Config.Rarities)
local Formulas = require(Shared.Config.Formulas)

local Screen = {}
local FREE_EGG = "MeadowEgg" -- profile.freeHatches applies to this egg (HatchService.FREE_EGG)
local ui = {}
local EGG_ORDER = { "MeadowEgg", "ForestEgg", "VolcanoEgg", "PremiumEgg" }

local function pct(p: number): string
	if p >= 0.01 then
		return string.format("%.2f%%", p * 100)
	elseif p >= 0.0001 then
		return string.format("%.4f%%", p * 100)
	end
	return string.format("%.6f%%", p * 100)
end

function Screen.showOdds(ctx, eggId)
	local C, Theme, Net = ctx.C, ctx.Theme, ctx.Net
	local ok, err, odds = Net.invoke("GetHatchOdds", eggId)
	if not ok then
		ctx.toast(err, "bad")
		return
	end
	local content = C.modal(ctx.gui, odds.displayName .. " - Odds", UDim2.fromOffset(560, 460))
	local header = string.format(
		"Price: %d %s.   Every outcome and its exact chance (sums to 100%%).",
		odds.price.amount,
		odds.price.currency
	)
	if odds.luck > 0 then
		header ..= string.format(
			"\nLuck boost active: +%d%% Rare+ odds (%s). Odds below already include it.",
			math.floor(odds.luck * 100 + 0.5),
			odds.luckCharges > 0 and (odds.luckCharges .. " hatches left") or "permanent"
		)
	end
	C.label({
		Size = UDim2.new(1, 0, 0, 48),
		Text = header,
		TextSize = 9,
		ZIndex = 53,
		Parent = content,
	})
	local scroll = C.scroll({
		Size = UDim2.new(1, 0, 1, -56),
		Position = UDim2.fromOffset(0, 52),
		ZIndex = 53,
		Parent = content,
	})
	C.list(scroll, 2)
	local order = 0
	for _, rarity in Rarities.Order do
		local p = odds.byRarity[rarity]
		if p and p > 0 then
			order += 1
			C.label({
				Size = UDim2.new(1, 0, 0, 18),
				Text = string.format("%s  %s", rarity, pct(p)),
				TextSize = 10,
				TextColor3 = Theme.Rarity[rarity],
				LayoutOrder = order,
				ZIndex = 54,
				Parent = scroll,
			})
			for _, row in odds.rows do
				if row.rarity == rarity then
					order += 1
					C.label({
						Size = UDim2.new(1, 0, 0, 14),
						Text = string.format(
							"     %-18s %s",
							Pets[row.petId].displayName,
							pct(row.odds)
						),
						TextSize = 9,
						TextColor3 = Theme.Colors.textDim,
						LayoutOrder = order,
						ZIndex = 54,
						Parent = scroll,
					})
				end
			end
		end
	end
end

local function showResults(ctx, results)
	local C, Theme = ctx.C, ctx.Theme
	local content = C.modal(ctx.gui, "Hatched!", UDim2.fromOffset(420, 120 + #results * 40))
	C.list(content, 6)
	for i, r in results do
		local def = Pets[r.petId]
		local card = C.frame({
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = Theme.Colors.panelLight,
			LayoutOrder = i,
			ZIndex = 53,
			Parent = content,
		})
		C.stroke(card, Theme.Rarity[r.rarity])
		C.label({
			Size = UDim2.new(1, -12, 1, 0),
			Position = UDim2.fromOffset(8, 0),
			Text = string.format(
				"%s  %s  %s%s",
				r.rarity,
				def.displayName,
				def.element,
				r.isNew and "   NEW!" or ""
			),
			TextSize = 11,
			TextColor3 = Theme.Rarity[r.rarity],
			ZIndex = 54,
			Parent = card,
		})
	end
end

local function refresh(ctx)
	local C, Theme, State, Net = ctx.C, ctx.Theme, ctx.State, ctx.Net
	for _, child in ui.cards:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local p = State.profile
	for i, eggId in EGG_ORDER do
		local egg = Eggs[eggId]
		local card = C.panel(
			{ Size = UDim2.fromOffset(196, 300), LayoutOrder = i, Parent = ui.cards },
			egg.displayName
		)
		local y = 40
		local function line(text, color, size)
			local l = C.label({
				Size = UDim2.new(1, -16, 0, size or 16),
				Position = UDim2.fromOffset(8, y),
				Text = text,
				TextSize = 9,
				TextColor3 = color or Theme.Colors.text,
				Parent = card,
			})
			y += (size or 16) + 2
			return l
		end
		-- egg "sprite": stacked blocks
		local egg1 = C.frame({
			Size = UDim2.fromOffset(60, 70),
			Position = UDim2.new(0.5, 0, 0, 44),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = eggId == "PremiumEgg" and Theme.Colors.gems
				or Theme.Element[({ "Grass", "Dark", "Fire" })[egg.zone or 1]],
			Parent = card,
		})
		C.stroke(egg1)
		y = 124
		line(
			string.format("%d %s", egg.price.amount, egg.price.currency),
			Theme.currencyColor(egg.price.currency),
			18
		)
		local ok, _, odds = Net.invoke("GetHatchOdds", eggId)
		if ok then
			local top = {}
			for _, r in { "Legendary", "Mythic", "Secret" } do
				if odds.byRarity[r] then
					table.insert(top, r .. " " .. pct(odds.byRarity[r]))
				end
			end
			line(table.concat(top, "\n"), Theme.Colors.textDim, 36)
			if not odds.available then
				line(odds.unavailableReason or "Locked", Theme.Colors.bad, 30)
			end
		end
		C.button({
			Size = UDim2.new(1, -16, 0, 26),
			Position = UDim2.new(0, 8, 1, -100),
			Text = "Details (odds)",
			BackgroundColor3 = Theme.Colors.panelLight,
			TextSize = 9,
			Parent = card,
		}, function()
			Screen.showOdds(ctx, eggId)
		end)
		local available = ok and odds.available
		local free = eggId == FREE_EGG and (p.freeHatches or 0) > 0
		local canAfford = available and (free or (p[egg.price.currency] or 0) >= egg.price.amount)
		local b1 = C.button({
			Name = if free then "HatchFree" else "Hatch1_" .. eggId,
			Size = UDim2.new(1, -16, 0, 28),
			Position = UDim2.new(0, 8, 1, -68),
			Text = if free then "Hatch x1 (FREE)" else "Hatch x1",
			BackgroundColor3 = if free then Theme.Colors.accent else Theme.Colors.good,
			TextSize = 10,
			Parent = card,
		}, function()
			local okH, err, results = Net.invoke("HatchEgg", eggId, 1)
			if okH then
				showResults(ctx, results)
			else
				ctx.toast(err, "bad")
			end
		end)
		C.setEnabled(b1, canAfford)
		local hasTriple = p.passes and p.passes.TripleHatch
		local b3 = C.button({
			Size = UDim2.new(1, -16, 0, 28),
			Position = UDim2.new(0, 8, 1, -36),
			Text = hasTriple and "Hatch x3" or "Hatch x3 (pass)",
			BackgroundColor3 = Theme.Colors.accent,
			TextSize = 10,
			Parent = card,
		}, function()
			if not hasTriple then
				ctx.Screens.open("Shop")
				return
			end
			local okH, err, results = Net.invoke("HatchEgg", eggId, 3)
			if okH then
				showResults(ctx, results)
			else
				ctx.toast(err, "bad")
			end
		end)
		C.setEnabled(
			b3,
			available and (p[egg.price.currency] or 0) >= egg.price.amount * 3 or not hasTriple
		)
	end
	ui.luck.Text = (p.luckCharges or 0) > 0
			and string.format(
				"Luck Potion active: +%d%% Rare+ odds for %d more hatches",
				math.floor((p.luck or 0) * 100 + 0.5),
				p.luckCharges
			)
		or ""
	local _ = Formulas
end

function Screen.build(host, ctx)
	Screen.ctx = ctx
	local C, Theme = ctx.C, ctx.Theme
	local root = C.panel({
		Name = "Hatch",
		Size = UDim2.fromOffset(860, 420),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = host,
	}, "Hatchery")
	ui.cards = C.frame({
		Size = UDim2.new(1, -16, 0, 300),
		Position = UDim2.fromOffset(8, 40),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.list(ui.cards, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	ui.luck = C.label({
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.new(0, 8, 1, -60),
		TextSize = 10,
		TextColor3 = Theme.Colors.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = root,
	})
	C.label({
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.new(0, 8, 1, -38),
		Text = "Odds are shown before every purchase and include any active luck boost. Pets are never lost: dismantle extras for shards, or fuse 5 identical pets into a Golden variant.",
		TextSize = 8,
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Center,
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
	ctx.State.onKeys(
		{ "coins", "gems", "luckCharges", "passes", "stages", "freeHatches" },
		function()
			if root.Visible then
				refresh(ctx)
			end
		end
	)
	return root
end

function Screen.onOpen()
	refresh(Screen.ctx)
end

return Screen
