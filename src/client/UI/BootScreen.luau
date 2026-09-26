--!nonstrict
-- Full-screen loading screen with a live checklist (connect -> server -> save) and on-screen
-- diagnostics, so a screenshot of a stuck load says exactly which step is stuck and why.
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.PixelTheme)
local C = require(script.Parent.Components)

local BootScreen = {}
BootScreen.__index = BootScreen

local STEPS = {
	{ id = "connect", text = "Connect to server" },
	{ id = "server", text = "Start game services" },
	{ id = "save", text = "Load your save" },
}
local MARK = { wait = "[  ]", ok = "[OK]", warn = "[!!]", fail = "[XX]" }
local HINT_AFTER = 20 -- s before the "take a screenshot" hint appears

function BootScreen.new(playerGui)
	local self = setmetatable({ started = os.clock(), rows = {} }, BootScreen)
	local gui = Instance.new("ScreenGui")
	gui.Name = "VoxelPetsBoot"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.None -- cover the top bar too
	gui.DisplayOrder = 900
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	self.gui = gui

	self.bg = C.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.bg,
		Parent = gui,
	})
	local box = C.panel({
		Size = UDim2.new(0.94, 0, 0, 340),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = self.bg,
	}, "VOXEL PETS")
	C.new("UISizeConstraint", { MaxSize = Vector2.new(640, 340), Parent = box })
	self.box = box

	self.title = C.label({
		Size = UDim2.new(1, -120, 0, 24),
		Position = UDim2.fromOffset(14, 42),
		Text = "Loading your pets...",
		TextSize = 14,
		Parent = box,
	})
	self.elapsed = C.label({
		Size = UDim2.fromOffset(90, 24),
		Position = UDim2.new(1, -104, 0, 42),
		Text = "0s",
		TextSize = 11,
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = box,
	})
	for i, step in STEPS do
		self.rows[step.id] = {
			text = step.text,
			state = "wait",
			detail = nil,
			label = C.label({
				Size = UDim2.new(1, -28, 0, 20),
				Position = UDim2.fromOffset(14, 76 + (i - 1) * 24),
				TextSize = 11,
				Parent = box,
			}),
		}
		self:set(step.id, "wait")
	end
	self.details = C.label({
		Size = UDim2.new(1, -28, 0, 132),
		Position = UDim2.fromOffset(14, 154),
		Text = "",
		TextSize = 13,
		FontFace = Theme.monoFont(),
		TextColor3 = Theme.Colors.textDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = box,
	})
	self.hint = C.label({
		Size = UDim2.new(1, -28, 0, 28),
		Position = UDim2.new(0, 14, 1, -36),
		Text = "Stuck here? Take a screenshot of this screen and send it to the developer.",
		TextSize = 9,
		TextColor3 = Theme.Colors.accent,
		Visible = false,
		Parent = box,
	})
	return self
end

local function rowColor(state)
	if state == "ok" then
		return Theme.Colors.good
	elseif state == "fail" then
		return Theme.Colors.bad
	elseif state == "warn" then
		return Theme.Colors.accent
	elseif state == "active" then
		return Theme.Colors.text
	end
	return Theme.Colors.textDim
end

local function render(self, row)
	local mark = MARK[row.state]
	if row.state == "active" then
		mark = "[" .. string.rep(".", 1 + math.floor((os.clock() - self.started) * 3) % 2) .. " ]"
		mark = string.sub(mark .. "    ", 1, 4)
	end
	row.label.Text = mark .. " " .. row.text .. (if row.detail then " - " .. row.detail else "")
	row.label.TextColor3 = rowColor(row.state)
end

-- state: "wait" | "active" | "ok" | "warn" | "fail"
function BootScreen:set(id: string, state: string, detail: string?)
	local row = self.rows[id]
	if not row then
		return
	end
	row.state, row.detail = state, detail
	render(self, row)
end

function BootScreen:problem(text: string?)
	self.details.Text = text or ""
end

function BootScreen:setTitle(text: string)
	self.title.Text = text
end

-- Call every frame-ish while waiting: animates active rows, elapsed time, hint.
function BootScreen:tick()
	local t = os.clock() - self.started
	self.elapsed.Text = string.format("%ds", math.floor(t))
	for _, row in self.rows do
		if row.state == "active" then
			render(self, row)
		end
	end
	if t > HINT_AFTER then
		self.hint.Visible = true
	end
end

function BootScreen:elapsedSeconds(): number
	return os.clock() - self.started
end

function BootScreen:destroy()
	local gui = self.gui
	if not gui or not gui.Parent then
		return
	end
	local tween = TweenService:Create(self.bg, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
	self.box.Visible = false
	tween:Play()
	task.delay(0.4, function()
		gui:Destroy()
	end)
end

return BootScreen
