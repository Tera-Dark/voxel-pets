--!nonstrict
-- Daily quests + 7-day login rewards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Quests = require(Shared.Config.Quests)
local DailyRewards = require(Shared.Config.DailyRewards)

local Screen = {}
local ui = {}

local function rewardText(reward)
	local parts = {}
	for _, key in { "coins", "gems", "essence", "tickets" } do
		if reward[key] then
			table.insert(parts, reward[key] .. " " .. key)
		end
	end
	return table.concat(parts, " + ")
end

local function clear(frame)
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function render(ctx)
	local C, Theme, State, Net = ctx.C, ctx.Theme, ctx.State, ctx.Net
	local p = State.profile
	clear(ui.list)
	local q = p.quests
	local claimedCount = 0
	for i, def in Quests.Daily do
		local progress = math.min(def.goal, (q.progress and q.progress[def.key]) or 0)
		local claimed = q.claimed and q.claimed[def.id]
		if claimed then
			claimedCount += 1
		end
		local row = C.frame({
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = i,
			BackgroundColor3 = Theme.Colors.panelLight,
			Parent = ui.list,
		})
		C.label({
			Size = UDim2.new(0, 300, 1, 0),
			Position = UDim2.fromOffset(8, 0),
			Text = def.displayName,
			TextSize = 9,
			Parent = row,
		})
		local bar = C.bar(
			{ Size = UDim2.fromOffset(160, 14), Position = UDim2.fromOffset(310, 13), Parent = row },
			Theme.Colors.info,
			Theme.Colors.bg
		)
		bar.set(progress / def.goal, string.format("%d / %d", progress, def.goal))
		C.label({
			Size = UDim2.fromOffset(150, 1),
			Position = UDim2.fromOffset(480, 0),
			Text = rewardText(def.reward),
			TextSize = 8,
			TextColor3 = Theme.Colors.accent,
			Parent = row,
		}).Size =
			UDim2.new(0, 150, 1, 0)
		local btn = C.button({
			Size = UDim2.fromOffset(100, 26),
			Position = UDim2.new(1, -108, 0, 7),
			Text = claimed and "Claimed" or "Claim",
			TextSize = 9,
			BackgroundColor3 = claimed and Theme.Colors.panel or Theme.Colors.good,
			Parent = row,
		}, function()
			local ok, err, rewards = Net.invoke("ClaimQuest", def.id)
			if ok then
				ctx.toast(
					"Quest reward: "
						.. rewardText(rewards)
						.. (rewards.bonus and "  (+all-complete bonus!)" or ""),
					"good"
				)
			else
				ctx.toast(err, "bad")
			end
		end)
		C.setEnabled(btn, not claimed and progress >= def.goal)
	end
	ui.bonus.Text = string.format(
		"Complete all %d quests for +%d gems.  Claimed %d / %d.  Quests reset daily at 00:00 UTC.",
		#Quests.Daily,
		Quests.AllCompleteBonus.gems,
		claimedCount,
		#Quests.Daily
	)

	-- daily login strip
	clear(ui.daily)
	local streak = p.stats.loginStreak or 0
	local today = os.date("!%Y-%m-%d")
	local yesterday = os.date("!%Y-%m-%d", os.time() - 86400)
	local lastClaim = p.stats.lastDailyClaim
	local claimedToday = lastClaim == today
	local continuing = streak > 0 and (claimedToday or lastClaim == yesterday)
	local pos = continuing and ((streak - 1) % #DailyRewards) + 1 or 0 -- cycle position of the last claim
	local nextDay = (pos % #DailyRewards) + 1
	for day = 1, #DailyRewards do
		local reward = DailyRewards[day]
		local color = Theme.Colors.panelLight
		if claimedToday and day == pos then
			color = Theme.Colors.good
		elseif not claimedToday and day == nextDay then
			color = Theme.Colors.info
		elseif day <= pos then
			color = Theme.Colors.panel
		end
		local cell = C.frame({
			Size = UDim2.fromOffset(104, 56),
			LayoutOrder = day,
			BackgroundColor3 = color,
			Parent = ui.daily,
		})
		C.label({
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.fromOffset(0, 4),
			Text = "Day " .. day,
			TextSize = 8,
			Parent = cell,
		})
		C.label({
			Size = UDim2.new(1, -4, 0, 30),
			Position = UDim2.fromOffset(2, 22),
			Text = rewardText(reward),
			TextSize = 7,
			TextColor3 = Theme.Colors.accent,
			Parent = cell,
		})
	end
	ui.dailyBtn.Text = claimedToday and ("Claimed today (streak " .. streak .. ")")
		or "CLAIM DAILY REWARD"
	C.setEnabled(ui.dailyBtn, not claimedToday)
end

function Screen.build(host, ctx)
	Screen.ctx = ctx
	local C, Theme = ctx.C, ctx.Theme
	local root = C.panel({
		Name = "Quests",
		Size = UDim2.fromOffset(780, 470),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = host,
	}, "Daily Quests")
	ui.list = C.frame({
		Size = UDim2.new(1, -16, 0, 6 * 44),
		Position = UDim2.fromOffset(8, 36),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.list(ui.list, 4)
	ui.bonus = C.label({
		Size = UDim2.new(1, -16, 0, 16),
		Position = UDim2.fromOffset(8, 306),
		TextSize = 8,
		TextColor3 = Theme.Colors.textDim,
		Parent = root,
	})
	C.label({
		Size = UDim2.new(1, -16, 0, 16),
		Position = UDim2.fromOffset(8, 330),
		Text = "LOGIN REWARDS (7-day cycle, streak resets if you miss a day)",
		TextSize = 9,
		TextColor3 = Theme.Colors.accent,
		Parent = root,
	})
	ui.daily = C.frame({
		Size = UDim2.new(1, -16, 0, 56),
		Position = UDim2.fromOffset(8, 350),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.list(ui.daily, 4, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	ui.dailyBtn = C.button({
		Size = UDim2.fromOffset(300, 32),
		Position = UDim2.new(0.5, -150, 1, -44),
		Text = "CLAIM DAILY REWARD",
		TextSize = 10,
		BackgroundColor3 = Theme.Colors.good,
		Parent = root,
	}, function()
		local ok, err, reward = ctx.Net.invoke("ClaimDaily")
		if ok then
			ctx.toast(string.format("Day %d reward: %s", reward.day, rewardText(reward)), "good")
		else
			ctx.toast(err, "bad")
		end
	end)
	C.button({
		Size = UDim2.fromOffset(28, 24),
		Position = UDim2.new(1, -31, 0, 3),
		Text = "X",
		BackgroundColor3 = Theme.Colors.bad,
		Parent = root,
	}, function()
		ctx.Screens.close()
	end)
	ctx.State.onKeys({ "quests", "stats" }, function()
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
