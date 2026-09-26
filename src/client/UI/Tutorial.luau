--!nonstrict
-- Client side of the new-player tutorial (shared/Config/Tutorial): partner picker, a pointer on
-- the next button to press, and a celebration when it is done. The server validates progress and
-- pays the reward; the client only guides, so nothing here can soft-lock a player.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local TutorialConfig = require(Shared.Config.Tutorial)
local Pets = require(Shared.Config.Pets)
local Skills = require(Shared.Config.Skills)
local Features = require(Shared.Config.Features)
local Formulas = require(Shared.Config.Formulas)
local PetInstance = require(Shared.Progression.PetInstance)

local Highlight = require(script.Parent.Highlight)
local PetModelFactory = require(script.Parent.Parent.World.PetModelFactory)

local Tutorial = {}

local ROLE_TEXT = {
	Attacker = "Hits hard and fast.",
	Tank = "Tough - outlasts enemies.",
	Support = "Heals itself and endures.",
}

local ctx = nil
local pickerClose = nil
local lastStep = nil

local function find(name: string)
	return ctx.gui:FindFirstChild(name, true)
end

-- 3D preview of a pet inside a ViewportFrame (cosmetic; any failure just leaves it empty).
local function preview(parent, petId: string, z: number)
	local vpf = Instance.new("ViewportFrame")
	vpf.Size = UDim2.new(1, -16, 0, 110)
	vpf.Position = UDim2.fromOffset(8, 40)
	vpf.BackgroundColor3 = ctx.Theme.Colors.bg
	vpf.BorderSizePixel = 0
	vpf.ZIndex = z
	vpf.Parent = parent
	pcall(function()
		local camera = Instance.new("Camera")
		camera.Parent = vpf
		vpf.CurrentCamera = camera
		local model = PetModelFactory.build(petId, "Normal", CFrame.new(0, 0, 0), 1)
		model.Parent = vpf
		camera.CFrame = CFrame.lookAt(Vector3.new(3.6, 2.4, 3.6), Vector3.new(0, 1.1, 0))
	end)
	return vpf
end

function Tutorial.openStarterPicker()
	if pickerClose then
		return
	end
	local C, Theme = ctx.C, ctx.Theme
	local content, close = C.modal(ctx.gui, "Choose your partner!", UDim2.fromOffset(700, 430))
	pickerClose = function()
		pickerClose = nil
		close()
	end
	C.label({
		Size = UDim2.new(1, 0, 0, 36),
		LineHeight = 1.2,
		Text = "Your partner fights for you automatically. Elements matter: "
			.. "Fire beats Grass, Grass beats Water, Water beats Fire.",
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 53,
		Parent = content,
	})
	local row = C.frame({
		Size = UDim2.new(1, 0, 1, -44),
		Position = UDim2.fromOffset(0, 42),
		BackgroundTransparency = 1,
		ZIndex = 53,
		Parent = content,
	})
	C.list(row, 12, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	-- level-1 stats, each bar relative to the best of the three (the trade-offs at a glance)
	local STATS = { { "hp", "HP", "maxHp" }, { "atk", "ATK" }, { "def", "DEF" }, { "spd", "SPD" } }
	local stats, best = {}, {}
	for _, petId in TutorialConfig.STARTERS do
		local st = Formulas.finalStats(Pets[petId], PetInstance.new(petId, "preview"), 1)
		stats[petId] = st
		for _, row in STATS do
			local v = st[row[1]] or st[row[3] or ""] or 0
			best[row[1]] = math.max(best[row[1]] or 0, v)
		end
	end
	for i, petId in TutorialConfig.STARTERS do
		local def = Pets[petId]
		local skill = Skills[def.skill]
		local color = Theme.Element[def.element] or Theme.Colors.panelLight
		local card = C.panel({
			Name = "Starter_" .. petId,
			Size = UDim2.fromOffset(212, 330),
			BackgroundColor3 = Theme.Colors.panel,
			LayoutOrder = i,
			ZIndex = 53,
			Parent = row,
		})
		C.frame({
			Size = UDim2.new(1, 0, 0, 8),
			BackgroundColor3 = color,
			ZIndex = 54,
			Parent = card,
		})
		C.label({
			Size = UDim2.new(1, -16, 0, 22),
			Position = UDim2.fromOffset(8, 14),
			Text = def.displayName,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 54,
			Parent = card,
		})
		preview(card, petId, 54)
		C.label({
			Size = UDim2.new(1, -16, 0, 18),
			Position = UDim2.fromOffset(8, 156),
			Text = def.element .. "  " .. def.role,
			TextSize = 9,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 54,
			Parent = card,
		})
		for r, row in STATS do
			local st = stats[petId]
			local v = st[row[1]] or st[row[3] or ""] or 0
			local y = 222 + (r - 1) * 12
			C.label({
				Size = UDim2.fromOffset(36, 10),
				Position = UDim2.fromOffset(14, y),
				Text = row[2],
				TextSize = 7,
				TextColor3 = Theme.Colors.textDim,
				ZIndex = 54,
				Parent = card,
			})
			local bar = C.bar({
				Size = UDim2.new(1, -66, 0, 8),
				Position = UDim2.fromOffset(52, y + 1),
				ZIndex = 54,
				Parent = card,
			}, color, Theme.Colors.bg)
			bar.set(if best[row[1]] > 0 then math.max(0.15, v / best[row[1]]) else 0)
			bar.text.Visible = false
			bar.fill.ZIndex = 55
		end
		C.label({
			Size = UDim2.new(1, -16, 0, 40),
			Position = UDim2.fromOffset(8, 178),
			Text = (ROLE_TEXT[def.role] or "")
				.. (if skill then "\nSkill: " .. (skill.displayName or def.skill) else ""),
			TextSize = 8,
			TextColor3 = Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 54,
			Parent = card,
		})
		C.button({
			Name = "Choose",
			Size = UDim2.new(1, -24, 0, 40),
			Position = UDim2.new(0, 12, 1, -52),
			Text = "CHOOSE",
			TextSize = 12,
			BackgroundColor3 = Theme.Colors.good,
			ZIndex = 55,
			Parent = card,
		}, function()
			local ok, err = ctx.Net.invoke("ChooseStarter", petId)
			if ok then
				if pickerClose then
					pickerClose()
				end
				ctx.toast(def.displayName .. " is your partner! Tap BATTLE to fight.", "good")
			else
				ctx.toast(err, "bad")
			end
		end)
	end
end

local function celebrate()
	local C, Theme = ctx.C, ctx.Theme
	ctx.tutorialJustFinished = os.clock()
	local content, close = C.modal(ctx.gui, "Tutorial complete!", UDim2.fromOffset(440, 250))
	local nextFeature = Features.nextLocked(ctx.State.profile)
	C.label({
		Size = UDim2.new(1, 0, 1, -56),
		LineHeight = 1.3,
		Text = string.format(
			"Great job, trainer!\n\n+%d gems\nQuests and Shop are now open.\n\n%s",
			TutorialConfig.REWARD.gems or 0,
			if nextFeature
				then "Next: "
					.. Features.requirement(nextFeature.id)
					.. " to unlock "
					.. nextFeature.label
					.. "."
				else ""
		),
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 53,
		Parent = content,
	})
	C.button({
		Size = UDim2.fromOffset(180, 38),
		Position = UDim2.new(0.5, -90, 1, -44),
		Text = "LET'S GO",
		BackgroundColor3 = Theme.Colors.good,
		ZIndex = 54,
		Parent = content,
	}, close)
end

-- Which button to point at for the current step and screen, and what to say.
local function pointer(step)
	local current = ctx.Screens.current()
	local hud = ctx.hud
	if step.id == "battle" or step.id == "stage2" then
		if current == "Battle" then
			return nil
		elseif current == "Stages" then
			return find("FightButton"), "Tap FIGHT - your pet battles on its own!"
		elseif current == nil then
			return hud and hud.battleButton,
				if step.id == "battle"
					then "Tap BATTLE to fight your first wild pet!"
					else "One more win: beat stage 1-2!"
		end
	elseif step.id == "hatch" then
		if current == "Hatch" then
			return find("HatchFree"), "Your first egg is FREE - tap to hatch!"
		elseif current == nil then
			local button = hud and hud.dock.button("Hatch")
			return button, "New: Hatch! Open it to get a second pet."
		end
	end
	return nil
end

function Tutorial.update()
	local p = ctx.State.profile
	if not p then
		return
	end
	local step = TutorialConfig.current(p)
	local stepIndex = p.tutorialStep or 0
	if
		lastStep ~= nil
		and lastStep < TutorialConfig.COUNT
		and stepIndex == TutorialConfig.COUNT
	then
		Highlight.hide()
		celebrate()
	end
	lastStep = stepIndex
	if not step then
		Highlight.hide()
		if pickerClose then
			pickerClose()
		end
		return
	end
	if step.id == "starter" then
		Highlight.hide()
		return
	end
	local target, message = pointer(step)
	if target then
		Highlight.show(target, message)
	else
		Highlight.hide()
	end
end

function Tutorial.start(context)
	ctx = context
	ctx.tutorial = Tutorial
	ctx.State.onKeys({ "tutorialStep", "stages", "stats", "pets", "freeHatches" }, function()
		task.defer(Tutorial.update)
	end)
	ctx.Screens.Opened:Connect(function()
		task.defer(Tutorial.update)
	end)
	local p = ctx.State.profile
	lastStep = p and p.tutorialStep or 0
	if p and TutorialConfig.current(p) and TutorialConfig.current(p).id == "starter" then
		task.delay(0.6, Tutorial.openStarterPicker)
	end
	Tutorial.update()
end

return Tutorial
