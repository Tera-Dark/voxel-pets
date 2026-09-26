--!nonstrict
-- Pet detail panel: stats and every progression action (level / evolve / star / team / lock /
-- rename / fuse / dismantle). Rendering only; all mutations go through Net + server validation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Skills = require(Shared.Config.Skills)
local Formulas = require(Shared.Config.Formulas)
local Rarities = require(Shared.Config.Rarities)
local PetInstance = require(Shared.Progression.PetInstance)

local PetsDetail = {}

-- Row factories: keep the layout order flowing down the detail column.
local function builder(ctx, parent)
	local C, Theme = ctx.C, ctx.Theme
	local order = 0
	local b = {}
	function b.row(text, size, color)
		order += 1
		return C.label({
			Size = UDim2.new(1, 0, 0, size or 18),
			Text = text,
			TextSize = (size or 18) > 20 and 14 or 10,
			TextColor3 = color or Theme.Colors.text,
			LayoutOrder = order,
			Parent = parent,
		})
	end
	function b.buttonRow(buttons)
		order += 1
		local r = C.frame({
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = parent,
		})
		C.list(r, 6, Enum.FillDirection.Horizontal)
		for _, btnDef in buttons do
			local btn = C.button({
				Size = UDim2.fromOffset(btnDef.w or 110, 28),
				Text = btnDef.text,
				BackgroundColor3 = btnDef.color or Theme.Colors.info,
				TextSize = 9,
				Parent = r,
			}, btnDef.fn)
			if btnDef.disabled then
				C.setEnabled(btn, false)
			end
		end
	end
	return b
end

local function headerSection(b, ctx, inst, def, stats, power, mult)
	local Theme, State = ctx.Theme, ctx.State
	local title = State.petName(inst)
	if inst.variant ~= "Normal" then
		title = Rarities.VariantDisplay[inst.variant] .. " " .. title
	end
	b.row(title, 26, Theme.Rarity[def.rarity])
	b.row(
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
	b.row(
		string.format(
			"Level %d / %d    XP %d / %d",
			inst.level,
			PetInstance.levelCap(inst),
			inst.xp,
			PetInstance.xpToNext(inst.level)
		),
		18
	)
	b.row(
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
		b.row("Skill: " .. sk.displayName .. " - " .. sk.description, 34, Theme.Colors.accent)
	end
	if def.passive then
		b.row("Passive: " .. def.passive, 16, Theme.Colors.info)
	end
	if mult > 1 then
		b.row(
			string.format("Account bonus x%.3f (codex + prestige)", mult),
			14,
			Theme.Colors.textDim
		)
	end
end

local function levelSection(b, ctx, uid, inst)
	local Net = ctx.Net
	local canLevel = PetInstance.canLevelUp(inst)
	local cost1 = PetInstance.levelUpCost(inst)
	local function level(times)
		return function()
			local ok, err = Net.invoke("LevelUpPet", uid, times)
			if not ok then
				ctx.toast(err, "bad")
			end
		end
	end
	b.buttonRow({
		{
			text = "Level +1 (" .. Formulas.formatNumber(cost1) .. ")",
			w = 150,
			disabled = not canLevel,
			fn = level(1),
		},
		{ text = "Level +10", w = 100, disabled = not canLevel, fn = level(10) },
		{ text = "Max", w = 70, disabled = not canLevel, fn = level(100) },
	})
end

local function evolveSection(b, ctx, uid, inst)
	local Theme, Net = ctx.Theme, ctx.Net
	local canEvolve, whyEvolve = PetInstance.canEvolve(inst)
	local evoCost = PetInstance.evolveCost(inst)
	local canStar = PetInstance.canStarUp(inst)
	b.buttonRow({
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
				local ok, err = Net.invoke("EvolvePet", uid)
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
				local ok, err = Net.invoke("StarUpPet", uid)
				ctx.toast(ok and "Star up!" or err, ok and "good" or "bad")
			end,
		},
	})
end

function PetsDetail.promptRename(ctx, uid)
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
		local ok, err = ctx.Net.invoke("RenamePet", uid, name)
		ctx.toast(ok and "Renamed" or err, ok and "good" or "bad")
		close()
	end)
	btn.ZIndex = 53
end

local function teamSection(b, ctx, uid, inst)
	local Theme, State, Net = ctx.Theme, ctx.State, ctx.Net
	local busy = State.isBusy(uid)
	b.buttonRow({
		{
			text = busy == "Active" and "Active pet" or "Set active",
			w = 120,
			color = Theme.Colors.good,
			disabled = busy == "Active",
			fn = function()
				local ok, err = Net.invoke("SetTeam", 1, uid)
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
				Net.invoke("SetPetLock", uid, not inst.locked)
			end,
		},
		{
			text = "Rename",
			w = 90,
			color = Theme.Colors.panelLight,
			fn = function()
				PetsDetail.promptRename(ctx, uid)
			end,
		},
	})
end

local function fuseSection(b, ctx, uid, inst, def)
	local C, Theme, State, Net = ctx.C, ctx.Theme, ctx.State, ctx.Net
	-- fusion candidates: same species + variant, unlocked, not busy
	local fuseList = {}
	for otherUid, other in State.profile.pets do
		if
			other.petId == inst.petId
			and other.variant == inst.variant
			and not other.locked
			and not State.isBusy(otherUid)
		then
			table.insert(fuseList, otherUid)
		end
	end
	table.sort(fuseList)
	local nextVariant = PetInstance.NEXT_VARIANT[inst.variant]
	local value = PetInstance.dismantleValue(inst)
	b.buttonRow({
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
			disabled = inst.locked or ctx.State.isBusy(uid) ~= nil,
			fn = function()
				C.confirm(
					ctx.gui,
					"Dismantle",
					"Dismantle " .. State.petName(inst) .. "? This cannot be undone.",
					function()
						local ok, err = Net.invoke("DismantlePets", { uid })
						ctx.toast(ok and "Dismantled" or err, ok and "good" or "bad")
					end
				)
			end,
		},
	})
end

-- Fills parent with the full detail column for the given instance (parent is cleared by the caller).
function PetsDetail.render(ctx, parent, inst, uid)
	local def = Pets[inst.petId]
	local mult = ctx.State.globalMult()
	local stats = Formulas.finalStats(def, inst, mult)
	local power = Formulas.power(stats)
	local b = builder(ctx, parent)
	headerSection(b, ctx, inst, def, stats, power, mult)
	levelSection(b, ctx, uid, inst)
	evolveSection(b, ctx, uid, inst)
	teamSection(b, ctx, uid, inst)
	fuseSection(b, ctx, uid, inst, def)
end

return PetsDetail
