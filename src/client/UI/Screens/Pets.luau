--!nonstrict
-- Pet collection: card list + selection state. The detail column (stats + all progression
-- actions) is rendered by PetsDetail to keep this screen small.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Config.Formulas)
local Rarities = require(Shared.Config.Rarities)
local PetsDetail = require(script.Parent.PetsDetail)

local Screen = {}
local ui = {}
local selectedUid = nil

local function petCard(ctx, parent, entry, selected, onClick)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State
	local inst, def = entry.inst, entry.def
	local card = C.button({
		Size = UDim2.new(1, -8, 0, 46),
		BackgroundColor3 = selected and Theme.Colors.panelLight or Theme.Colors.panel,
		Text = "",
		Parent = parent,
	}, onClick)
	local stripe = C.frame({
		Size = UDim2.new(0, 6, 1, 0),
		BackgroundColor3 = Theme.Rarity[def.rarity],
		Parent = card,
	})
	local _ = stripe
	local name = State.petName(inst)
	if inst.variant ~= "Normal" then
		name = Rarities.VariantDisplay[inst.variant] .. " " .. name
	end
	C.label({
		Size = UDim2.new(1, -60, 0, 18),
		Position = UDim2.fromOffset(12, 4),
		Text = name,
		TextSize = 10,
		Parent = card,
	})
	C.label({
		Size = UDim2.new(1, -60, 0, 14),
		Position = UDim2.fromOffset(12, 24),
		Text = string.format(
			"Lv%d  %s  P%s",
			inst.level,
			def.element,
			Formulas.formatNumber(entry.power)
		),
		TextSize = 9,
		TextColor3 = Theme.Colors.textDim,
		Parent = card,
	})
	local busy = State.isBusy(entry.uid)
	if busy then
		C.label({
			Size = UDim2.fromOffset(56, 14),
			Position = UDim2.new(1, -60, 0, 4),
			Text = busy,
			TextSize = 8,
			TextColor3 = busy == "Active" and Theme.Colors.good or Theme.Colors.info,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		})
	end
	if inst.locked then
		C.label({
			Size = UDim2.fromOffset(56, 14),
			Position = UDim2.new(1, -60, 0, 24),
			Text = "LOCK",
			TextSize = 8,
			TextColor3 = Theme.Colors.accent,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		})
	end
	return card
end

local function refreshList(ctx)
	local C = ctx.C
	for _, child in ui.list:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local list = ctx.State.petList()
	if selectedUid and not ctx.State.profile.pets[selectedUid] then
		selectedUid = nil
	end
	if not selectedUid and list[1] then
		selectedUid = list[1].uid
	end
	for i, entry in list do
		local card = petCard(ctx, ui.list, entry, entry.uid == selectedUid, function()
			selectedUid = entry.uid
			refreshList(ctx)
		end)
		card.LayoutOrder = i
	end
	ui.count.Text = string.format("%d / 200 pets", #list)
	Screen.refreshDetail(ctx)
	local _ = C
end

function Screen.refreshDetail(ctx)
	local C, State = ctx.C, ctx.State
	for _, child in ui.detail:GetChildren() do
		if not child:IsA("UIPadding") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local inst = selectedUid and State.profile.pets[selectedUid]
	if not inst then
		C.label({ Size = UDim2.new(1, 0, 0, 30), Text = "Select a pet", Parent = ui.detail })
		return
	end
	PetsDetail.render(ctx, ui.detail, inst, selectedUid)
end

function Screen.build(host, ctx)
	Screen.ctx = ctx
	local C, Theme = ctx.C, ctx.Theme
	local root = C.panel({
		Name = "Pets",
		Size = UDim2.fromOffset(860, 520),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = host,
	}, "Pets")
	local listPanel = C.frame({
		Size = UDim2.new(0, 300, 1, -40),
		Position = UDim2.fromOffset(8, 36),
		BackgroundColor3 = Theme.Colors.bg,
		Parent = root,
	})
	C.stroke(listPanel, Theme.Colors.border, 2)
	ui.count = C.label({
		Size = UDim2.new(1, -8, 0, 18),
		Position = UDim2.fromOffset(6, 2),
		TextSize = 9,
		TextColor3 = Theme.Colors.textDim,
		Parent = listPanel,
	})
	ui.list = C.scroll({
		Size = UDim2.new(1, 0, 1, -22),
		Position = UDim2.fromOffset(0, 22),
		Parent = listPanel,
	})
	C.list(ui.list, 4)
	C.padding(ui.list, 4)
	ui.detail = C.frame({
		Size = UDim2.new(1, -324, 1, -40),
		Position = UDim2.fromOffset(316, 36),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.list(ui.detail, 6)
	C.padding(ui.detail, 4)
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
		{ "pets", "team", "camp", "coins", "expedition", "essence", "shards" },
		function()
			if root.Visible then
				refreshList(ctx)
			end
		end
	)
	return root
end

function Screen.onOpen(frame, arg)
	if type(arg) == "string" then
		selectedUid = arg
	end
	refreshList(Screen.ctx)
	local _ = frame
end

return Screen
