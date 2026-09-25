--!nonstrict
-- Pet collection: list + detail with all progression actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Skills = require(Shared.Config.Skills)
local Formulas = require(Shared.Config.Formulas)
local Rarities = require(Shared.Config.Rarities)
local PetInstance = require(Shared.Progression.PetInstance)

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
	local C, Theme, State, Net = ctx.C, ctx.Theme, ctx.State, ctx.Net
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
	local def = Pets[inst.petId]
	local mult = State.globalMult()
	local stats = Formulas.finalStats(def, inst, mult)
	local power = Formulas.power(stats)
	local order = 0
	local function row(text, size, color)
		order += 1
		return C.label({
			Size = UDim2.new(1, 0, 0, size or 18),
			Text = text,
			TextSize = (size or 18) > 20 and 14 or 10,
			TextColor3 = color or Theme.Colors.text,
			LayoutOrder = order,
			Parent = ui.detail,
		})
	end
	local function buttonRow(buttons)
		order += 1
		local r = C.frame({
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = ui.detail,
		})
		C.list(r, 6, Enum.FillDirection.Horizontal)
		for _, b in buttons do
			local btn = C.button({
				Size = UDim2.fromOffset(b.w or 110, 28),
				Text = b.text,
				BackgroundColor3 = b.color or Theme.Colors.info,
				TextSize = 9,
				Parent = r,
			}, b.fn)
			if b.disabled then
				C.setEnabled(btn, false)
			end
		end
	end

	local title = State.petName(inst)
	if inst.variant ~= "Normal" then
		title = Rarities.VariantDisplay[inst.variant] .. " " .. title
	end
	row(title, 26, Theme.Rarity[def.rarity])
	row(
		string.format(
			"%s  %s  %s   Stars %d/%d  Evo %d/3",
			def.rarity,
			def.element,
			def.role,
			inst.stars,
			6,
			inst.evolution
		),
		16,
		Theme.Colors.textDim
	)
	row(
		string.format(
			"Level %d / %d    XP %d / %d",
			inst.level,
			PetInstance.levelCap(inst),
			inst.xp,
			PetInstance.xpToNext(inst.level)
		),
		18
	)
	row(
		string.format(
			"Power %s   HP %s  ATK %d  DEF %d  SPD %d  CRIT %d%%",
			Formulas.formatNumber(power),
			Formulas.formatNumber(stats.hp),
			stats.atk,
			stats.def,
			stats.spd,
			math.floor(stats.crit * 100)
		),
		18
	)
	if def.skill then
		local sk = Skills[def.skill]
		row("Skill: " .. sk.displayName .. " - " .. sk.description, 34, Theme.Colors.accent)
	end
	if def.passive then
		row("Passive: " .. def.passive, 16, Theme.Colors.info)
	end
	if mult > 1 then
		row(string.format("Account bonus x%.3f (codex + prestige)", mult), 14, Theme.Colors.textDim)
	end

	local canLevel = PetInstance.canLevelUp(inst)
	local cost1 = PetInstance.levelUpCost(inst)
	local busy = State.isBusy(selectedUid)
	buttonRow({
		{
			text = "Level +1 (" .. Formulas.formatNumber(cost1) .. ")",
			w = 150,
			disabled = not canLevel,
			fn = function()
				local ok, err = Net.invoke("LevelUpPet", selectedUid, 1)
				if not ok then
					ctx.toast(err, "bad")
				end
			end,
		},
		{
			text = "Level +10",
			w = 100,
			disabled = not canLevel,
			fn = function()
				local ok, err = Net.invoke("LevelUpPet", selectedUid, 10)
				if not ok then
					ctx.toast(err, "bad")
				end
			end,
		},
		{
			text = "Max",
			w = 70,
			disabled = not canLevel,
			fn = function()
				local ok, err = Net.invoke("LevelUpPet", selectedUid, 100)
				if not ok then
					ctx.toast(err, "bad")
				end
			end,
		},
	})
	local canEvolve, whyEvolve = PetInstance.canEvolve(inst)
	local evoCost = PetInstance.evolveCost(inst)
	local canStar = PetInstance.canStarUp(inst)
	buttonRow({
		{
			text = canEvolve and string.format(
				"Evolve (%d ess, %s c)",
				evoCost.essence,
				Formulas.formatNumber(evoCost.coins)
			) or ("Evolve: " .. tostring(whyEvolve)),
			w = 200,
			color = Theme.Colors.essence,
			disabled = not canEvolve,
			fn = function()
				local ok, err = Net.invoke("EvolvePet", selectedUid)
				ctx.toast(ok and "Evolved!" or err, ok and "good" or "bad")
			end,
		},
		{
			text = canStar and ("Star up (" .. PetInstance.starUpCost(inst) .. " shards)")
				or "Max stars",
			w = 170,
			color = Theme.Colors.shards,
			disabled = not canStar,
			fn = function()
				local ok, err = Net.invoke("StarUpPet", selectedUid)
				ctx.toast(ok and "Star up!" or err, ok and "good" or "bad")
			end,
		},
	})
	buttonRow({
		{
			text = busy == "Active" and "Active pet" or "Set active",
			w = 120,
			color = Theme.Colors.good,
			disabled = busy == "Active",
			fn = function()
				local ok, err = Net.invoke("SetTeam", 1, selectedUid)
				if not ok then
					ctx.toast(err, "bad")
				end
			end,
		},
		{
			text = inst.locked and "Unlock" or "Lock",
			w = 80,
			color = Theme.Colors.panelLight,
			fn = function()
				Net.invoke("SetPetLock", selectedUid, not inst.locked)
			end,
		},
		{
			text = "Rename",
			w = 90,
			color = Theme.Colors.panelLight,
			fn = function()
				Screen.promptRename(ctx)
			end,
		},
	})
	-- fusion candidates: same species + variant, unlocked, not busy
	local fuseList = {}
	for uid, other in State.profile.pets do
		if
			other.petId == inst.petId
			and other.variant == inst.variant
			and not other.locked
			and not State.isBusy(uid)
		then
			table.insert(fuseList, uid)
		end
	end
	table.sort(fuseList)
	local nextVariant = PetInstance.NEXT_VARIANT[inst.variant]
	local value = PetInstance.dismantleValue(inst)
	buttonRow({
		{
			text = nextVariant
					and string.format("Fuse 5 -> %s (%d/5)", nextVariant, math.min(5, #fuseList))
				or "Max variant",
			w = 200,
			color = Theme.Colors.accent,
			disabled = not nextVariant or #fuseList < 5,
			fn = function()
				local five = { table.unpack(fuseList, 1, 5) }
				C.confirm(
					ctx.gui,
					"Fuse",
					string.format(
						"Fuse 5 %s into one %s %s? Best level/stars are kept.",
						def.displayName,
						nextVariant,
						def.displayName
					),
					function()
						local ok, err = Net.invoke("FusePets", five)
						ctx.toast(ok and "Fused!" or err, ok and "good" or "bad")
					end
				)
			end,
		},
		{
			text = string.format("Dismantle (+%d shards)", value.shards),
			w = 190,
			color = Theme.Colors.bad,
			disabled = inst.locked or busy ~= nil,
			fn = function()
				C.confirm(
					ctx.gui,
					"Dismantle",
					"Dismantle " .. State.petName(inst) .. "? This cannot be undone.",
					function()
						local ok, err = Net.invoke("DismantlePets", { selectedUid })
						ctx.toast(ok and "Dismantled" or err, ok and "good" or "bad")
					end
				)
			end,
		},
	})
end

function Screen.promptRename(ctx)
	local C = ctx.C
	local content, close = C.modal(ctx.gui, "Rename", UDim2.fromOffset(360, 160))
	local box = C.new("TextBox", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = ctx.Theme.Colors.bg,
		TextColor3 = ctx.Theme.Colors.text,
		FontFace = ctx.Theme.font(),
		TextSize = 12,
		PlaceholderText = "New name (max 16)",
		Text = "",
		ClearTextOnFocus = false,
		ZIndex = 53,
		Parent = content,
	})
	C.stroke(box)
	local btn = C.button({
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.fromOffset(0, 50),
		Text = "Save",
		BackgroundColor3 = ctx.Theme.Colors.good,
		ZIndex = 53,
		Parent = content,
	}, function()
		local name = box.Text:sub(1, 16)
		if #name == 0 then
			return
		end
		local ok, err = ctx.Net.invoke("RenamePet", selectedUid, name)
		ctx.toast(ok and "Renamed" or err, ok and "good" or "bad")
		close()
	end)
	btn.ZIndex = 53
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
