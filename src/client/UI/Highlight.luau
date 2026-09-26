--!nonstrict
-- Tutorial pointer: a pulsing outline, a speech bubble and a bouncing arrow that follow a target
-- GuiObject every frame (targets move when the dock collapses, screens open, the UI scales).
-- Lives in its own ScreenGui above the HUD; hidden automatically while the target is hidden.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.PixelTheme)
local C = require(script.Parent.Components)
local PixelIcons = require(script.Parent.PixelIcons)

local Highlight = {}

local ui = nil
local target = nil
local conn = nil

local function ensure()
	if ui and ui.gui.Parent then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "VoxelPetsTutorial"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false -- same space as the HUD, so AbsolutePosition lines up
	gui.DisplayOrder = 800
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local outline =
		C.frame({ Name = "Outline", BackgroundTransparency = 1, Visible = false, Parent = gui })
	local stroke = C.stroke(outline, Theme.Colors.accent, 4)
	TweenService:Create(
		stroke,
		TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.65 }
	):Play()
	local bubble = C.panel({
		Name = "Bubble",
		Size = UDim2.fromOffset(300, 46),
		BackgroundColor3 = Theme.Colors.accent,
		Visible = false,
		Parent = gui,
	})
	local text = C.label({
		Name = "Text",
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		TextSize = 10,
		TextColor3 = Theme.Colors.bg,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = bubble,
	})
	local arrows = {}
	for _, name in { "arrowDown", "arrowUp", "arrowLeft" } do
		arrows[name] = PixelIcons.new(name, 30, { Name = name, Visible = false, Parent = gui })
	end
	ui = { gui = gui, outline = outline, bubble = bubble, text = text, arrows = arrows }
end

local function shownOnScreen(obj): boolean
	local o = obj
	while o and o:IsA("GuiObject") do
		if not o.Visible then
			return false
		end
		o = o.Parent
	end
	return o ~= nil and obj.AbsoluteSize.X > 0
end

local function setVisible(on: boolean, arrowName: string?)
	ui.outline.Visible = on
	ui.bubble.Visible = on
	for name, icon in ui.arrows do
		icon.Visible = on and name == arrowName
	end
end

-- Where the bubble goes (mirrored by scripts/render_ui.py): right of targets on the left edge,
-- above targets in the lower half, below otherwise when there is room.
function Highlight.placement(pos: Vector2, size: Vector2, viewport: Vector2): string
	local cy = pos.Y + size.Y / 2
	if pos.X + size.X < viewport.X * 0.22 and cy < viewport.Y * 0.8 then
		return "right"
	elseif cy > viewport.Y * 0.55 then
		return "above"
	elseif pos.Y + size.Y + 46 + 50 < viewport.Y then
		return "below"
	end
	return "above"
end

local function place()
	if not target or not target.Parent or not shownOnScreen(target) then
		setVisible(false)
		return
	end
	local pos, size = target.AbsolutePosition, target.AbsoluteSize
	ui.outline.Position = UDim2.fromOffset(pos.X - 6, pos.Y - 6)
	ui.outline.Size = UDim2.fromOffset(size.X + 12, size.Y + 12)
	local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
		or Vector2.new(1280, 720)
	local bw, bh = 300, 46
	local bob = math.sin(os.clock() * 6) * 4
	local cx, cy = pos.X + size.X / 2, pos.Y + size.Y / 2
	local mode = Highlight.placement(pos, size, viewport)
	local maxX = math.max(8, viewport.X - bw - 8)
	local arrowName
	if mode == "right" then
		ui.bubble.Position = UDim2.fromOffset(pos.X + size.X + 44, cy - bh / 2)
		arrowName = "arrowLeft"
		ui.arrows.arrowLeft.Position = UDim2.fromOffset(pos.X + size.X + 10 - bob, cy - 15)
	elseif mode == "above" then
		ui.bubble.Position = UDim2.fromOffset(math.clamp(cx - bw / 2, 8, maxX), pos.Y - bh - 40)
		arrowName = "arrowDown"
		ui.arrows.arrowDown.Position = UDim2.fromOffset(cx - 15, pos.Y - 38 + bob)
	else
		ui.bubble.Position = UDim2.fromOffset(math.clamp(cx - bw / 2, 8, maxX), pos.Y + size.Y + 40)
		arrowName = "arrowUp"
		ui.arrows.arrowUp.Position = UDim2.fromOffset(cx - 15, pos.Y + size.Y + 8 - bob)
	end
	setVisible(true, arrowName)
end

-- Points at obj with a message. Calling again with another target moves the pointer.
function Highlight.show(obj, message: string)
	ensure()
	target = obj
	ui.text.Text = message
	if not conn then
		conn = RunService.RenderStepped:Connect(function()
			local ok = pcall(place)
			if not ok then
				Highlight.hide()
			end
		end)
	end
	place()
end

function Highlight.hide()
	target = nil
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if ui then
		setVisible(false)
	end
end

function Highlight.current()
	return target, ui and ui.text.Text or nil
end

return Highlight
