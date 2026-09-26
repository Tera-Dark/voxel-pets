--!nonstrict
-- Bottom of the HUD: the active pet chip (left, opens Pets) and the BATTLE call-to-action (right,
-- opens the next stage to play).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Formulas = require(Shared.Config.Formulas)
local Stages = require(Shared.Config.Stages)
local PetInstance = require(Shared.Progression.PetInstance)

local PixelIcons = require(script.Parent.Parent.PixelIcons)

local ActionBar = {}

ActionBar.KEYS = { "team", "pets", "codex", "prestige", "stages" }

function ActionBar.build(root, ctx)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State

	-- active pet chip -------------------------------------------------------------------------
	local chip = C.button({
		Name = "PetChip",
		Size = UDim2.fromOffset(230, 56),
		Position = UDim2.new(0, 10, 1, -66),
		Text = "",
		BackgroundColor3 = Theme.Colors.panel,
		Parent = root,
	}, function()
		ctx.openFeature("Pets")
	end)
	local swatch = C.frame({
		Name = "Swatch",
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Theme.Colors.panelLight,
		Parent = chip,
	})
	C.stroke(swatch, Theme.Colors.border, 2)
	PixelIcons.new("paw", 30, { Position = UDim2.fromOffset(5, 5), Parent = swatch })
	local name = C.label({
		Name = "PetName",
		Size = UDim2.new(1, -62, 0, 18),
		Position = UDim2.fromOffset(56, 6),
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = chip,
	})
	local info = C.label({
		Size = UDim2.new(1, -62, 0, 14),
		Position = UDim2.fromOffset(56, 24),
		TextSize = 8,
		TextColor3 = Theme.Colors.textDim,
		Parent = chip,
	})
	local xp = C.bar(
		{ Size = UDim2.new(1, -66, 0, 8), Position = UDim2.fromOffset(56, 41), Parent = chip },
		Theme.Colors.info,
		Theme.Colors.bg
	)
	xp.text.Visible = false

	-- battle CTA ------------------------------------------------------------------------------
	local battle = C.button({
		Name = "BattleButton",
		Size = UDim2.fromOffset(176, 60),
		Position = UDim2.new(1, -186, 1, -68),
		Text = "",
		BackgroundColor3 = Theme.Colors.bad,
		Parent = root,
	}, function()
		local zone, stage = Stages.nextStage(State.profile and State.profile.stages)
		ctx.Screens.open("Stages", { zone = zone, stage = stage })
	end)
	PixelIcons.new("sword", 30, { Position = UDim2.fromOffset(12, 15), Parent = battle })
	C.label({
		Size = UDim2.new(1, -60, 0, 26),
		Position = UDim2.fromOffset(52, 8),
		Text = "BATTLE",
		TextSize = 16,
		Parent = battle,
	})
	local sub = C.label({
		Name = "NextStage",
		Size = UDim2.new(1, -60, 0, 16),
		Position = UDim2.fromOffset(52, 36),
		Text = "",
		TextSize = 8,
		TextColor3 = Color3.fromRGB(255, 226, 226),
		Parent = battle,
	})

	local function refresh()
		local p = State.profile
		if not p then
			return
		end
		local inst = State.teamPet()
		if inst then
			local def = Pets[inst.petId]
			name.Text = State.petName(inst) .. "  Lv" .. inst.level
			info.Text = string.format(
				"%s  Power %s",
				def.element,
				Formulas.formatNumber(
					Formulas.power(Formulas.finalStats(def, inst, State.globalMult()))
				)
			)
			swatch.BackgroundColor3 = Theme.Element[def.element] or Theme.Colors.panelLight
			local need = PetInstance.xpToNext(inst.level)
			xp.set(if need > 0 then (inst.xp or 0) / need else 1)
		else
			name.Text = "Pick an active pet"
			info.Text = "Tap to open Pets"
			swatch.BackgroundColor3 = Theme.Colors.panelLight
			xp.set(0)
		end
		local zone, stage = Stages.nextStage(p.stages)
		sub.Text = "Stage " .. zone .. "-" .. stage
	end
	State.onKeys(ActionBar.KEYS, refresh)
	refresh()
	local api = { chip = chip, battle = battle, refresh = refresh }
	-- Portrait: the chip and BATTLE sit in one row above the dock. Landscape: dock between them.
	function api.relayout(portrait: boolean, dockHeight: number)
		if portrait then
			local bottom = dockHeight + 8
			chip.Position = UDim2.new(0, 10, 1, -(bottom + 60))
			battle.Position = UDim2.new(1, -10, 1, -(bottom + 62))
		else
			chip.Position = UDim2.new(0, 10, 1, -66)
			battle.Position = UDim2.new(1, -186, 1, -68)
		end
	end
	return api
end

return ActionBar
