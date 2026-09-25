--!nonstrict
-- Collection codex: every species by zone, discovered variants, completion bonus.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Rarities = require(Shared.Config.Rarities)
local Stages = require(Shared.Config.Stages)
local Codex = require(Shared.Progression.Codex)

local Screen = {}
local ui = {}
local VARIANT_TAG = { Normal = "N", Golden = "G", Rainbow = "R", DarkMatter = "D" }

local function clear(frame)
	for _, child in frame:GetChildren() do
		if
			not child:IsA("UIGridLayout")
			and not child:IsA("UIListLayout")
			and not child:IsA("UIPadding")
		then
			child:Destroy()
		end
	end
end

local function render(ctx)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State
	clear(ui.grid)
	local codex = State.profile.codex or {}
	local summary = Codex.summary(codex)
	ui.header.Text = string.format(
		"Species %d / %d   Variants %d   Zones complete %d / %d   Stat bonus x%.3f",
		summary.species,
		summary.totalSpecies,
		summary.variants,
		summary.zonesComplete,
		#Stages.Zones,
		Codex.bonusMult(codex)
	)
	local order = 0
	local listed = {}
	local function card(petId, zoneLabel)
		order += 1
		listed[petId] = true
		local def = Pets[petId]
		local seen = codex[petId]
		local c =
			C.panel({ Size = UDim2.fromOffset(150, 74), LayoutOrder = order, Parent = ui.grid })
		local name = seen and def.displayName or "???"
		C.label({
			Size = UDim2.new(1, -8, 0, 16),
			Position = UDim2.fromOffset(4, 4),
			Text = name,
			TextSize = 8,
			TextColor3 = seen and Theme.Rarity[def.rarity] or Theme.Colors.textDim,
			Parent = c,
		})
		C.label({
			Size = UDim2.new(1, -8, 0, 14),
			Position = UDim2.fromOffset(4, 22),
			Text = string.format("%s  %s  %s", def.rarity, seen and def.element or "?", zoneLabel),
			TextSize = 7,
			TextColor3 = Theme.Colors.textDim,
			Parent = c,
		})
		local x = 4
		for _, v in Rarities.Variants do
			local has = seen and seen[v]
			local tag = C.label({
				Size = UDim2.fromOffset(30, 18),
				Position = UDim2.fromOffset(x, 44),
				Text = VARIANT_TAG[v],
				TextSize = 8,
				TextColor3 = has and Theme.Colors.text or Theme.Colors.borderLight,
				Parent = c,
			})
			tag.BackgroundTransparency = 0
			tag.BackgroundColor3 = has and (Theme.Variant and Theme.Variant[v] or Theme.Colors.good)
				or Theme.Colors.bg
			x += 34
		end
	end
	for zone = 1, #Stages.Zones do
		for _, petId in Codex.zoneSpecies(zone) do
			card(petId, "Z" .. zone)
		end
	end
	-- everything else (starters, egg-only, expedition exclusives)
	local rest = {}
	for petId in Pets do
		if not listed[petId] then
			table.insert(rest, petId)
		end
	end
	table.sort(rest, function(a, b)
		local ra = table.find(Rarities.Order, Pets[a].rarity) or 0
		local rb = table.find(Rarities.Order, Pets[b].rarity) or 0
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	for _, petId in rest do
		local def = Pets[petId]
		card(petId, def.starter and "Starter" or (def.expeditionOnly and "Expedition" or "Egg"))
	end
end

function Screen.build(host, ctx)
	Screen.ctx = ctx
	local C, Theme = ctx.C, ctx.Theme
	local root = C.panel({
		Name = "Codex",
		Size = UDim2.fromOffset(860, 500),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = host,
	}, "Codex")
	ui.header = C.label({
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(8, 36),
		TextSize = 9,
		TextColor3 = Theme.Colors.textDim,
		Parent = root,
	})
	C.label({
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.fromOffset(8, 54),
		Text = "Each species +0.3% stats, each variant +0.2%, each complete zone +3%.  N normal  G golden  R rainbow  D dark matter",
		TextSize = 7,
		TextColor3 = Theme.Colors.textDim,
		Parent = root,
	})
	local scroll = C.scroll({
		Size = UDim2.new(1, -16, 1, -80),
		Position = UDim2.fromOffset(8, 72),
		Parent = root,
	})
	ui.grid = scroll
	C.grid(scroll, 150, 74, 6)
	C.button({
		Size = UDim2.fromOffset(28, 24),
		Position = UDim2.new(1, -31, 0, 3),
		Text = "X",
		BackgroundColor3 = Theme.Colors.bad,
		Parent = root,
	}, function()
		ctx.Screens.close()
	end)
	ctx.State.onKeys({ "codex" }, function()
		if root.Visible then
			render(ctx)
		end
	end)
	return root
end

function Screen.onOpen()
	render(Screen.ctx)
end

return Screen
