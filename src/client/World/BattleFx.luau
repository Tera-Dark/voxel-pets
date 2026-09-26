--!nonstrict
-- Shared arena + effect kit for battle playback (used by BattleStage).
-- Everything here is cosmetic and mock-safe: built-in sounds are pcall-guarded, effects are
-- anchored neon cubes animated with TweenService (Position/Transparency/CFrame only).
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Elements = require(Shared.Config.Elements)
local Theme = require(script.Parent.Parent.UI.PixelTheme)

local BattleFx = {}

-- ---------------------------------------------------------------- sound kit
-- Built-in rbxasset clips only (no uploads, no moderation): a missing clip is silent, never
-- an error. Small pitch variance keeps repeats from sounding mechanical.
local SFX = {
	clash = { id = "rbxasset://sounds/snap.mp3", volume = 0.5 },
	heavy = { id = "rbxasset://sounds/bass.wav", volume = 0.6 },
	swoosh = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.45 },
	land = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.5 },
	ping = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.4 },
	ko = { id = "rbxasset://sounds/uuhhh.mp3", volume = 0.65 },
}

function BattleFx.sfx(name: string, pitch: number?)
	local def = SFX[name]
	if not def then
		return
	end
	pcall(function()
		local s = Instance.new("Sound")
		s.Name = "SFX_" .. name
		s.SoundId = def.id
		s.Volume = def.volume
		s.PlaybackSpeed = pitch or (0.92 + math.random() * 0.16)
		s.Parent = BattleFx.ensureStage()
		s:Play()
		task.delay(2, function()
			s:Destroy()
		end)
	end)
end

-- ---------------------------------------------------------------- arena
function BattleFx.rgb(hex: { number }): Color3
	return Color3.fromRGB(hex[1], hex[2], hex[3])
end

-- The "voxel clash" arena: a long flat platform with team strips, gold center line,
-- backdrop wall and corner posts, all in the game's warm palette.
function BattleFx.ensureStage()
	local folder = Workspace:FindFirstChild("BattleStage")
	if folder then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = "BattleStage"
	-- local slab: parents straight into the folder being built (no re-entry into ensureStage)
	local function slab(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.SmoothPlastic
		for k, v in props do
			p[k] = v
		end
		p.Parent = folder
		return p
	end
	local wood, dark, gold, sand =
		Theme.Colors.panel, Theme.Colors.bg, Theme.Colors.borderLight, Theme.Colors.parchment
	local origin = BattleFx.ORIGIN
	slab({
		Name = "Floor",
		Size = Vector3.new(58, 2, 18),
		Position = origin - Vector3.new(0, 1, 0),
		Color = sand,
	})
	slab({
		Name = "Rim",
		Size = Vector3.new(58, 0.6, 18.6),
		Position = origin - Vector3.new(0, 2, 0),
		Color = dark,
	})
	slab({
		Name = "CenterLine",
		Size = Vector3.new(0.8, 0.15, 18),
		Position = origin + Vector3.new(0, 0.08, 0),
		Color = gold,
	})
	for i = 1, 2 do
		local side = i == 1 and "A" or "B"
		slab({
			Name = "Strip" .. side,
			Size = Vector3.new(2.4, 0.15, 18),
			Position = origin + Vector3.new(BattleFx.HOME[side].X, 0.08, 0),
			Color = if i == 1 then Theme.Colors.good else Theme.Colors.bad,
		})
	end
	slab({
		Name = "Wall",
		Size = Vector3.new(58, 14, 1.5),
		Position = origin + Vector3.new(0, 6, 10.2),
		Color = dark,
	})
	slab({
		Name = "WallTrim",
		Size = Vector3.new(58, 0.5, 1.7),
		Position = origin + Vector3.new(0, 13, 10.2),
		Color = gold,
	})
	for _, x in { -28, 28 } do
		for _, z in { -8.4, 8.4 } do
			slab({
				Name = "Post",
				Size = Vector3.new(1.4, 4.4, 1.4),
				Position = origin + Vector3.new(x, 1.2, z),
				Color = wood,
			})
			slab({
				Name = "PostCap",
				Size = Vector3.new(1.8, 0.5, 1.8),
				Position = origin + Vector3.new(x, 3.6, z),
				Color = gold,
			})
		end
	end
	folder.Parent = Workspace
	return folder
end

BattleFx.ORIGIN = Vector3.new(0, 300, 0)
BattleFx.HOME = { A = Vector3.new(-8, 0, 0), B = Vector3.new(8, 0, 0) } -- lane spots on X

-- ---------------------------------------------------------------- effects
-- Floating combat text (billboard that rises and fades).
function BattleFx.floatText(position: Vector3, text: string, color: Color3, size: number?)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Position = position
	holder.Parent = BattleFx.ensureStage()
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(180, 44)
	bb.AlwaysOnTop = true
	bb.Parent = holder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.FontFace = Theme.font()
	label.TextSize = size or 18
	label.Parent = bb
	TweenService:Create(
		holder,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = position + Vector3.new(0, 3, 0) }
	):Play()
	TweenService
		:Create(label, TweenInfo.new(0.9), { TextTransparency = 1, TextStrokeTransparency = 1 })
		:Play()
	task.delay(1, function()
		holder:Destroy()
	end)
end

-- A voxel burst: small neon cubes that fly out and fade. The workhorse of every hit.
function BattleFx.burst(position: Vector3, color: Color3, count: number?, power: number?)
	for _ = 1, count or 8 do
		local cube = Instance.new("Part")
		cube.Name = "Fx"
		cube.Anchored = true
		cube.CanCollide = false
		cube.CanQuery = false
		cube.Material = Enum.Material.Neon
		cube.Size = Vector3.new(0.25 + math.random() * 0.35, 0.25, 0.25 + math.random() * 0.35)
		cube.Position = position
		cube.Color = color
		cube.Parent = BattleFx.ensureStage()
		local dir =
			Vector3.new(math.random() - 0.5, math.random() * 0.9, (math.random() - 0.5) * 0.5)
		TweenService:Create(
			cube,
			TweenInfo.new(
				0.35 + math.random() * 0.25,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{ Position = position + dir * (power or 3), Transparency = 1 }
		):Play()
		task.delay(0.7, function()
			cube:Destroy()
		end)
	end
end

-- A flat ring of cubes racing outward along the ground (skill slams, KOs).
function BattleFx.shockwave(position: Vector3, color: Color3)
	for i = 1, 10 do
		local ang = (i / 10) * math.pi * 2
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local cube = Instance.new("Part")
		cube.Name = "Fx"
		cube.Anchored = true
		cube.CanCollide = false
		cube.CanQuery = false
		cube.Material = Enum.Material.Neon
		cube.Size = Vector3.new(0.6, 0.22, 0.6)
		cube.Position = position + Vector3.new(0, 0.15, 0)
		cube.Color = color
		cube.Parent = BattleFx.ensureStage()
		TweenService:Create(
			cube,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = position + dir * 5 + Vector3.new(0, 0.15, 0), Transparency = 1 }
		):Play()
		task.delay(0.8, function()
			cube:Destroy()
		end)
	end
end

function BattleFx.elementColor(petId: string?): Color3
	local def = petId and Pets[petId]
	local rgbTable = def and Elements.ColorRGB[def.element]
	return rgbTable and BattleFx.rgb(rgbTable) or Theme.Colors.text
end

-- Brief tint of every body part (hit feedback).
function BattleFx.flash(model, color)
	for _, p in model:GetDescendants() do
		if
			p:IsA("BasePart")
			and p.Name ~= "Eye"
			and p.Name ~= "EyeWhite"
			and p.Name ~= "Nameplate"
		then
			local original = p.Color
			p.Color = color
			task.delay(0.1, function()
				if p.Parent then
					p.Color = original
				end
			end)
		end
	end
end

-- Nameplate: name + HP bar + shield bar floating over a pet. set(hp, maxHp, shield) updates it.
function BattleFx.makeNameplate(model, side: string, name: string)
	local head = model:GetPivot().Position
		+ Vector3.new(0, (model:GetAttribute("Height") or 3) + 1.6, 0)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Position = head
	holder.Name = "Nameplate"
	holder.Parent = model
	local bb = Instance.new("BillboardGui")
	bb.Name = "Plate"
	bb.Size = UDim2.fromOffset(130, 40)
	bb.AlwaysOnTop = true
	bb.Parent = holder
	local tag = Instance.new("TextLabel")
	tag.Name = "Tag"
	tag.Size = UDim2.new(1, 0, 0, 14)
	tag.BackgroundTransparency = 1
	tag.Text = name
	tag.TextColor3 = if side == "A" then Theme.Colors.good else Theme.Colors.bad
	tag.TextStrokeTransparency = 0.5
	tag.FontFace = Theme.font()
	tag.TextSize = 10
	tag.Parent = bb
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.new(1, 0, 0, 10)
	back.Position = UDim2.fromOffset(0, 16)
	back.BackgroundColor3 = Theme.Colors.border
	back.BorderSizePixel = 0
	back.Parent = bb
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = if side == "A" then Theme.Colors.good else Theme.Colors.bad
	fill.BorderSizePixel = 0
	fill.Parent = back
	local shield = Instance.new("Frame")
	shield.Name = "Shield"
	shield.Size = UDim2.fromScale(0, 1)
	shield.Position = UDim2.fromOffset(0, -3)
	shield.BackgroundColor3 = Theme.Colors.info
	shield.BorderSizePixel = 0
	shield.Visible = false
	shield.Parent = back
	local api
	api = {
		set = function(hp, maxHp, shieldValue)
			fill.Size = UDim2.fromScale(math.clamp(hp / math.max(1, maxHp), 0, 1), 1)
			if shieldValue and shieldValue > 0 then
				shield.Visible = true
				shield.Size = UDim2.fromScale(math.clamp(shieldValue / math.max(1, maxHp), 0, 1), 1)
			else
				shield.Visible = false
			end
		end,
	}
	return api
end

return BattleFx
