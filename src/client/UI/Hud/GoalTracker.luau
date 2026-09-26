--!nonstrict
-- "What next?" bar under the currencies: the tutorial step, then the next feature unlock, then
-- daily quests. The whole bar is a button that jumps to the right place.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Features = require(Shared.Config.Features)
local Tutorial = require(Shared.Config.Tutorial)
local Stages = require(Shared.Config.Stages)
local Quests = require(Shared.Config.Quests)

local GoalTracker = {}

GoalTracker.KEYS = { "tutorialStep", "stages", "stats", "quests" }

-- Pure: { title, text, action, tutorial } for a profile. action is "starter" or
-- { screen = name, arg = openArg }.
function GoalTracker.goalFor(profile)
	local step, index = Tutorial.current(profile)
	if step then
		local action
		if step.id == "starter" then
			action = "starter"
		elseif step.id == "battle" then
			action = { screen = "Stages", arg = { zone = 1, stage = 1 } }
		elseif step.id == "hatch" then
			action = { screen = "Hatch" }
		else
			action = { screen = "Stages", arg = { zone = 1, stage = 2 } }
		end
		return {
			title = string.format("TUTORIAL  %d/%d", index, Tutorial.COUNT),
			text = step.goal,
			action = action,
			tutorial = true,
		}
	end
	local nextFeature = Features.nextLocked(profile)
	if nextFeature then
		local action
		if nextFeature.unlock and nextFeature.unlock.hatches then
			action = { screen = "Hatch" }
		else
			local zone, stage = Stages.nextStage(profile.stages)
			action = { screen = "Stages", arg = { zone = zone, stage = stage } }
		end
		return {
			title = "NEXT UNLOCK  >  " .. string.upper(nextFeature.label),
			text = Features.requirement(nextFeature.id),
			action = action,
		}
	end
	local done = 0
	local q = profile.quests or {}
	local today = q.date == Quests.dateKey()
	for _, quest in Quests.Daily do
		if today and ((q.progress or {})[quest.key] or 0) >= quest.goal then
			done += 1
		end
	end
	return {
		title = "DAILY",
		text = string.format("Daily quests  %d/%d", done, #Quests.Daily),
		action = { screen = "Quests" },
	}
end

-- opts.onAction(goal), opts.onSkip()
function GoalTracker.build(root, ctx, opts)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State
	local current = nil
	local panel = C.button({
		Name = "GoalTracker",
		Size = UDim2.fromOffset(310, 46),
		Position = UDim2.fromOffset(10, 46),
		Text = "",
		BackgroundColor3 = Theme.Colors.panel,
		Parent = root,
	}, function()
		if current then
			opts.onAction(current)
		end
	end)
	local title = C.label({
		Name = "Title",
		Size = UDim2.new(1, -70, 0, 14),
		Position = UDim2.fromOffset(10, 5),
		TextSize = 7,
		TextColor3 = Theme.Colors.accent,
		Parent = panel,
	})
	local text = C.label({
		Name = "Goal",
		Size = UDim2.new(1, -40, 0, 20),
		Position = UDim2.fromOffset(10, 21),
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = panel,
	})
	C.label({
		Size = UDim2.fromOffset(24, 46),
		Position = UDim2.new(1, -28, 0, 0),
		Text = ">",
		TextSize = 14,
		TextColor3 = Theme.Colors.accent,
		Parent = panel,
	})
	local skip = C.button({
		Name = "SkipTutorial",
		Size = UDim2.fromOffset(52, 16),
		Position = UDim2.new(1, -86, 0, 4),
		Text = "Skip",
		TextSize = 7,
		BackgroundColor3 = Theme.Colors.panelLight,
		Visible = false,
		Parent = panel,
	}, function()
		opts.onSkip()
	end)

	local function refresh()
		local p = State.profile
		if not p then
			return
		end
		current = GoalTracker.goalFor(p)
		title.Text = current.title
		text.Text = current.text
		-- the starter step cannot be skipped from here (the picker has its own choice)
		skip.Visible = current.tutorial == true and (p.tutorialStep or 0) >= 1
		panel:SetAttribute(
			"BaseColor",
			if current.tutorial then Theme.Colors.panelLight else Theme.Colors.panel
		)
	end
	State.onKeys(GoalTracker.KEYS, refresh)
	refresh()
	return {
		frame = panel,
		refresh = refresh,
		goal = function()
			return current
		end,
	}
end

return GoalTracker
