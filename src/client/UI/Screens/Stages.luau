--!nonstrict
-- PvE stage select: zone tabs, 10 stage buttons with stars, enemy preview, fight.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Skills = require(Shared.Config.Skills)
local Stages = require(Shared.Config.Stages)
local PixelIcons = require(script.Parent.Parent.PixelIcons)
local Elements = require(Shared.Config.Elements)
local Builder = require(Shared.Combat.Builder)
local Formulas = require(Shared.Config.Formulas)

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
			Size = UDim2.fromOffset(200, 30),
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
			PixelIcons.new("lock", 20, { Position = UDim2.fromOffset(10, 5), Parent = b })
		end
	end
	for _, child in ui.grid:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for s = 1, Stages.STAGES_PER_ZONE do
		local enemyId, kind = Stages.enemyFor(zone, s)
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
			BackgroundColor3 = s == stage and Theme.Colors.info
				or (
					kind == "Boss" and Theme.Colors.bad
					or (kind == "Elite" and Theme.Colors.essence or Theme.Colors.panelLight)
				),
			TextSize = 9,
			Parent = ui.grid,
		}, function()
			stage = s
			refresh(ctx)
		end)
		C.setEnabled(b, unlocked)
		local _ = enemyId
	end
	-- preview
	local enemyId, kind = Stages.enemyFor(zone, stage)
	local def = Pets[enemyId]
	local enemy = Builder.buildEnemy(enemyId, zone, stage, { side = "B", slot = 1 })
	local rewards = Stages.rewards(zone, stage)
	local mine = State.teamPet()
	local lines = {
		string.format("%s  (%s)", def.displayName, kind),
		string.format(
			"%s %s  Lv%d  Power %s",
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
		"",
		string.format(
			"Rewards: %d coins, %d xp%s",
			rewards.coins,
			rewards.xp,
			(p.stages[Stages.key(zone, stage)] or 0) == 0
					and (", first clear +" .. rewards.firstClearGems .. " gems")
				or ""
		),
	}
	if mine then
		local myDef = Pets[mine.petId]
		local myPower = Formulas.power(Formulas.finalStats(myDef, mine, State.globalMult()))
		local matchup = Elements.multiplier(myDef.element, def.element)
		local hint = matchup > 1 and "Your element is STRONG here"
			or (
				matchup < 1 and "Your element is WEAK here - consider another pet"
				or "Neutral matchup"
			)
		table.insert(lines, "")
		table.insert(
			lines,
			string.format(
				"Your %s: Power %s   %s",
				State.petName(mine),
				Formulas.formatNumber(myPower),
				hint
			)
		)
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
		Size = UDim2.fromOffset(860, 460),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = host,
	}, "Battle Gate")
	ui.tabs = C.frame({
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 38),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.list(ui.tabs, 6, Enum.FillDirection.Horizontal)
	ui.grid = C.frame({
		Size = UDim2.fromOffset(520, 150),
		Position = UDim2.fromOffset(8, 76),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.grid(ui.grid, 96, 64, 6)
	ui.preview = C.label({
		Size = UDim2.new(1, -16, 0, 150),
		Position = UDim2.fromOffset(8, 240),
		TextSize = 10,
		Parent = root,
	})
	ui.fight = C.button({
		Name = "FightButton",
		Size = UDim2.fromOffset(300, 48),
		Position = UDim2.new(1, -316, 0, 84),
		Text = "FIGHT",
		BackgroundColor3 = Theme.Colors.bad,
		TextSize = 14,
		Parent = root,
	}, function()
		C.setEnabled(ui.fight, false)
		local ok, err = ctx.Net.invoke("StartStage", zone, stage)
		if not ok then
			ctx.toast(err, "bad")
			C.setEnabled(ui.fight, true)
		end
	end)
	ui.fightHint = C.label({
		Name = "FightHint",
		Size = UDim2.fromOffset(300, 18),
		Position = UDim2.new(1, -316, 0, 136),
		Text = "",
		TextSize = 8,
		TextColor3 = Theme.Colors.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = root,
	})
	C.label({
		Size = UDim2.fromOffset(300, 80),
		Position = UDim2.new(1, -316, 0, 160),
		Text = "Fully automatic combat. Pick the right element, level up, or bring relics from expeditions. Stars: clear / finish above 50% HP / finish under 30s.",
		TextSize = 8,
		TextColor3 = Theme.Colors.textDim,
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
	ctx.State.onKeys({ "stages", "team", "pets" }, function()
		if root.Visible then
			refresh(ctx)
		end
	end)
	return root
end

function Screen.onOpen(frame, arg)
	local p = Screen.ctx.State.profile
	if type(arg) == "table" then
		zone, stage = arg.zone, arg.stage
	else
		-- jump to the furthest open stage
		for z = #Stages.Zones, 1, -1 do
			if Stages.isZoneUnlocked(z, p.stages) then
				zone = z
				stage = firstOpenStage(p.stages, z)
				break
			end
		end
	end
	refresh(Screen.ctx)
	local _ = frame
end

function Screen.current()
	return zone, stage
end

return Screen
