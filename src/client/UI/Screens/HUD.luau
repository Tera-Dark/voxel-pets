--!nonstrict
-- HUD assembler. Layout (1280x720 reference, UIScale adapts other screens):
--   top-left     coins + gems (+ expands the rest)           top-right  settings gear
--   below        goal tracker ("what next?")
--   left         dock: unlocked features only, grouped, collapsible
--   bottom       active pet chip (left) + BATTLE call-to-action (right)
-- Also: announcement ticker, server toasts, notification badges, live feature-unlock banners.
-- Handles are exposed on ctx.hud for the tutorial pointer.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Quests = require(Shared.Config.Quests)
local Tutorial = require(Shared.Config.Tutorial)
local PetInstance = require(Shared.Progression.PetInstance)

local UI = script.Parent.Parent
local TopBar = require(UI.Hud.TopBar)
local GoalTracker = require(UI.Hud.GoalTracker)
local Dock = require(UI.Hud.Dock)
local ActionBar = require(UI.Hud.ActionBar)
local PixelIcons = require(UI.PixelIcons)

local HUD = {}

local BADGE_KEYS = { "freeHatches", "quests", "stats", "coins", "pets", "team", "camp" }

-- Pure badge rules (exported for tests).
function HUD.questsClaimable(p): boolean
	local today = Quests.dateKey()
	if p.stats and p.stats.lastDailyClaim ~= today then
		return true
	end
	local q = p.quests
	if not q or q.date ~= today then
		return false
	end
	for _, quest in Quests.Daily do
		if
			((q.progress or {})[quest.key] or 0) >= quest.goal and not (q.claimed or {})[quest.id]
		then
			return true
		end
	end
	return false
end

function HUD.canLevelUp(p, inst): boolean
	return inst ~= nil
		and PetInstance.canLevelUp(inst)
		and (p.coins or 0) >= PetInstance.levelUpCost(inst)
end

-- Non-blocking "NEW feature" banners for live unlocks (the tutorial guides brand-new players).
-- Deferred a moment: the stage clear and the tutorial completion arrive as separate updates, and
-- the completion popup already announces what finishing the tutorial unlocks.
function HUD.unlockBanners(ctx, root, features)
	task.delay(0.6, function()
		local p = ctx.State.profile
		if not p or Tutorial.isActive(p) then
			return
		end
		if ctx.tutorialJustFinished and os.clock() - ctx.tutorialJustFinished < 5 then
			return
		end
		HUD.showBanners(ctx, root, features)
	end)
end

function HUD.showBanners(ctx, root, features)
	local C, Theme = ctx.C, ctx.Theme
	for i, f in features do
		local banner = C.panel({
			Name = "UnlockBanner",
			Size = UDim2.fromOffset(460, 72),
			Position = UDim2.new(0.5, 0, 0, 50 + (i - 1) * 80),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = 60,
			Parent = root,
		})
		local icon =
			PixelIcons.new(f.icon, 40, { Position = UDim2.fromOffset(14, 16), Parent = banner })
		PixelIcons.setZIndex(icon, 61)
		C.label({
			Size = UDim2.new(1, -180, 0, 22),
			Position = UDim2.fromOffset(66, 8),
			Text = "NEW: " .. f.label .. " unlocked!",
			TextSize = 11,
			TextColor3 = Theme.Colors.accent,
			ZIndex = 61,
			Parent = banner,
		})
		C.label({
			Size = UDim2.new(1, -180, 0, 34),
			Position = UDim2.fromOffset(66, 32),
			Text = f.blurb,
			TextSize = 8,
			TextColor3 = Theme.Colors.textDim,
			ZIndex = 61,
			Parent = banner,
		})
		C.button({
			Size = UDim2.fromOffset(92, 36),
			Position = UDim2.new(1, -104, 0.5, -18),
			Text = "OPEN",
			BackgroundColor3 = Theme.Colors.good,
			ZIndex = 61,
			Parent = banner,
		}, function()
			banner:Destroy()
			ctx.openFeature(f.id)
		end)
		task.delay(8, function()
			if banner.Parent then
				banner:Destroy()
			end
		end)
	end
end

function HUD.build(host, ctx)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State
	local root = C.frame({
		Name = "HUD",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = host,
	})

	local top = TopBar.build(root, ctx)
	local goal = GoalTracker.build(root, ctx, {
		onAction = function(g)
			if g.action == "starter" then
				if ctx.tutorial then
					ctx.tutorial.openStarterPicker()
				end
			elseif type(g.action) == "table" then
				if g.action.screen == "Stages" then
					ctx.Screens.open("Stages", g.action.arg)
				else
					ctx.openFeature(g.action.screen, g.action.arg)
				end
			end
		end,
		onSkip = function()
			C.confirm(
				ctx.gui,
				"Skip tutorial?",
				"Everything stays in the menu. The tutorial reward is only given for finishing it.",
				function()
					local ok, err = ctx.Net.invoke("TutorialSkip")
					if not ok then
						ctx.toast(err, "bad")
					end
				end
			)
		end,
	})
	local dock = Dock.build(root, ctx, {
		onOpen = function(id)
			ctx.openFeature(id)
		end,
		onUnlocked = function(features)
			HUD.unlockBanners(ctx, root, features)
		end,
		canvasWidth = function()
			return if ctx.canvasSize then ctx.canvasSize().X else 1280
		end,
	})
	local bar = ActionBar.build(root, ctx)

	-- announcement ticker (top centre, under the test-mode tag)
	local ticker = C.label({
		Name = "Ticker",
		Size = UDim2.fromOffset(600, 22),
		Position = UDim2.new(0.5, 0, 0, 26),
		AnchorPoint = Vector2.new(0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.accent,
		TextStrokeTransparency = 0,
		Text = "",
		Parent = root,
	})
	local queue, showing = {}, false
	local function pump()
		if showing or #queue == 0 then
			return
		end
		showing = true
		local item = table.remove(queue, 1)
		ticker.Text = item.text
		ticker.TextColor3 = Theme.Rarity[item.kind] or Theme.Colors.accent
		task.delay(5, function()
			ticker.Text = ""
			showing = false
			pump()
		end)
	end
	ctx.Net.on("Announcement", function(text, kind)
		if #queue < 5 then
			table.insert(queue, { text = tostring(text), kind = kind })
		end
		pump()
	end)
	ctx.Net.on("Toast", function(text, kind)
		ctx.toast(text, kind)
	end)

	-- notification badges ("!" on dock items)
	local function refreshBadges()
		local p = State.profile
		if not p then
			return
		end
		dock.setBadge("Hatch", (p.freeHatches or 0) > 0)
		dock.setBadge("Quests", HUD.questsClaimable(p))
		dock.setBadge("Pets", HUD.canLevelUp(p, State.teamPet()))
		local pending = p.camp and p.camp.pending
		dock.setBadge("Camp", pending ~= nil and (pending.coins or 0) >= 50)
	end
	State.onKeys(BADGE_KEYS, refreshBadges)
	refreshBadges()

	ctx.Screens.Opened:Connect(function(name)
		dock.onScreen(name)
		refreshBadges()
	end)

	ctx.hud = {
		root = root,
		top = top,
		goal = goal,
		dock = dock,
		battleButton = bar.battle,
		petChip = bar.chip,
		refreshBadges = refreshBadges,
	}
	return root
end

return HUD
