--!nonstrict
-- PvE stage select: zone tabs, stage buttons with stars, enemy preview on parchment, big FIGHT.
-- Flow layout (one vertical list) so it works from portrait phones to desktop; the stage grid
-- wraps and scrolls. Close button and pop-in come from ScreenManager.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Skills = require(Shared.Config.Skills)
local Stages = require(Shared.Config.Stages)
local Elements = require(Shared.Config.Elements)
local Builder = require(Shared.Combat.Builder)
local Formulas = require(Shared.Config.Formulas)
local PixelIcons = require(script.Parent.Parent.PixelIcons)

local Screen = {}
local ui = {}
local zone, stage = 1, 1

local function firstOpenStage(stagesData, z)
	for s = 1, Stages.STAGES_PER_ZONE do
		if (stagesData[Stages.key(z, s)] or 0) == 0 then
			return s
		end
	end
	return Stages.STAGES_PER_ZONE
end

local function refresh(ctx)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State
	local p = State.profile
	for _, child in ui.tabs:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for i, z in Stages.Zones do
		local unlocked = Stages.isZoneUnlocked(z.id, p.stages)
		local b = C.button({
			Name = "ZoneTab" .. z.id,
			Size = UDim2.fromOffset(150, 30),
			Text = (if unlocked then "" else "    ") .. z.displayName,
			LayoutOrder = i,
			BackgroundColor3 = z.id == zone and Theme.Colors.info or Theme.Colors.panelLight,
			TextSize = 9,
			Parent = ui.tabs,
		}, function()
			zone = z.id
			stage = firstOpenStage(p.stages, zone)
			refresh(ctx)
		end)
		C.setEnabled(b, unlocked)
		if not unlocked then
			PixelIcons.new("lock", 20, { Position = UDim2.fromOffset(8, 5), Parent = b })
		end
	end
	for _, child in ui.grid:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for s = 1, Stages.STAGES_PER_ZONE do
		local _, kind = Stages.enemyFor(zone, s)
		local stars = p.stages[Stages.key(zone, s)] or 0
		local unlocked = Stages.isStageUnlocked(zone, s, p.stages)
		local b = C.button({
			Size = UDim2.fromOffset(96, 64),
			Text = string.format(
				"%d-%d\n%s\n%s",
				zone,
				s,
				kind == "Normal" and "" or kind:upper(),
				if not unlocked
					then "LOCKED"
					elseif stars == 0 then "NEW"
					else string.rep("*", stars) .. string.rep("-", 3 - stars)
			),
			LayoutOrder = s,
			BackgroundColor3 = if s == stage
				then Theme.Colors.info
				else if kind == "Boss"
					then Theme.Colors.bad
					elseif kind == "Elite" then Theme.Colors.essence
					else Theme.Colors.panelLight,
			TextSize = 9,
			Parent = ui.grid,
		}, function()
			stage = s
			refresh(ctx)
		end)
		C.setEnabled(b, unlocked)
	end
	-- preview on parchment
	local enemyId, kind = Stages.enemyFor(zone, stage)
	local def = Pets[enemyId]
	local enemy = Builder.buildEnemy(enemyId, zone, stage, { side = "B", slot = 1 })
	local rewards = Stages.rewards(zone, stage)
	local mine = State.teamPet()
	local lines = {
		string.format(
			"%s  (%s)   %s %s  Lv%d   Power %s",
			def.displayName,
			kind,
			def.element,
			def.role,
			enemy.level,
			Formulas.formatNumber(enemy.power)
		),
		string.format(
			"HP %s  ATK %d  DEF %d  SPD %d",
			Formulas.formatNumber(enemy.maxHp),
			enemy.atk,
			enemy.def,
			enemy.spd
		),
		def.skill and ("Skill: " .. Skills[def.skill].displayName) or "No skill",
		string.format(
			"Rewards: %d coins, %d xp%s",
			rewards.coins,
			rewards.xp,
			if (p.stages[Stages.key(zone, stage)] or 0) == 0
				then ("   FIRST CLEAR: +" .. rewards.firstClearGems .. " gems")
				else ""
		),
	}
	if mine then
		local myDef = Pets[mine.petId]
		local matchup = Elements.multiplier(myDef.element, def.element)
		local hint = if matchup > 1
			then "Your element is STRONG here"
			elseif matchup < 1 then "Your element is WEAK here - another pet may do better"
			else "Neutral matchup"
		table.insert(lines, hint)
	end
	ui.preview.Text = table.concat(lines, "\n")
	ui.fight.Text = "FIGHT " .. zone .. "-" .. stage
	local stageOpen = Stages.isStageUnlocked(zone, stage, p.stages)
	C.setEnabled(ui.fight, stageOpen and mine ~= nil)
	-- a disabled button always says why
	ui.fightHint.Text = if mine == nil
		then "Pick an active pet first (Pets)."
		elseif not stageOpen then "Clear the previous stage first."
		else ""
end

function Screen.build(host, ctx)
	Screen.ctx = ctx
	local C, Theme = ctx.C, ctx.Theme
	local root = C.panel({
		Name = "Stages",
		Size = UDim2.fromScale(0.94, 0.92),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = host,
	}, "Battle Gate")
	C.new("UISizeConstraint", { MaxSize = Vector2.new(880, 560), Parent = root })

	local content = C.frame({
		Name = "Content",
		Size = UDim2.new(1, 0, 1, -34),
		Position = UDim2.fromOffset(0, 32),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.padding(content, 10)
	C.list(content, 8)

	ui.tabs = C.frame({
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		Parent = content,
	})
	C.list(ui.tabs, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)

	ui.grid = C.scroll({
		Name = "StageGrid",
		Size = UDim2.new(1, 0, 0, 148),
		BackgroundTransparency = 1,
		Parent = content,
	})
	C.grid(ui.grid, 96, 64, 6)

	local sheet = C.frame({
		Name = "PreviewSheet",
		Size = UDim2.new(1, 0, 0, 118),
		BackgroundColor3 = Theme.Colors.parchment,
		Parent = content,
	})
	C.bevel(sheet)
	ui.preview = C.label({
		Name = "Preview",
		Size = UDim2.new(1, -16, 1, -10),
		Position = UDim2.fromOffset(8, 5),
		Text = "",
		TextSize = 9,
		TextColor3 = Theme.Colors.textDark,
		Parent = sheet,
	})

	ui.fightHint = C.label({
		Name = "FightHint",
		Size = UDim2.new(1, 0, 0, 14),
		Text = "",
		TextSize = 8,
		TextColor3 = Theme.Colors.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = content,
	})
	ui.fight = C.button({
		Name = "FightButton",
		Size = UDim2.new(1, 0, 0, 54),
		Text = "FIGHT",
		BackgroundColor3 = Theme.Colors.bad,
		TextSize = 15,
		Parent = content,
	}, function()
		C.setEnabled(ui.fight, false)
		local ok, err = ctx.Net.invoke("StartStage", zone, stage)
		if not ok then
			ctx.toast(err, "bad")
			C.setEnabled(ui.fight, true)
		end
	end)
	ctx.State.onKeys({ "stages", "team", "pets" }, function()
		if root.Visible then
			refresh(ctx)
		end
	end)
	return root
end

-- The zone/stage this screen is on (the battle result actions use it for "Next").
function Screen.current(): (number, number)
	return zone, stage
end

function Screen.onOpen(_frame, arg)
	local p = Screen.ctx.State.profile
	if type(arg) == "table" then
		zone, stage = arg.zone, arg.stage
	else
		zone, stage = Stages.nextStage(p.stages) -- the frontier
	end
	refresh(Screen.ctx)
end

return Screen
