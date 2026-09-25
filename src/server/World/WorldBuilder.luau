--!nonstrict
-- Procedural voxel hub. Everything is plain Parts so the place file needs no external assets.
-- Each station has a ProximityPrompt; the part carries a "Screen" attribute the client opens.
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local WorldBuilder = {}

local PALETTE = {
	grass = Color3.fromRGB(96, 168, 78),
	grassDark = Color3.fromRGB(78, 140, 64),
	dirt = Color3.fromRGB(120, 86, 58),
	stone = Color3.fromRGB(140, 140, 150),
	stoneDark = Color3.fromRGB(100, 100, 112),
	wood = Color3.fromRGB(150, 105, 62),
	leaf = Color3.fromRGB(70, 150, 70),
	water = Color3.fromRGB(70, 140, 220),
	fire = Color3.fromRGB(240, 110, 50),
	dark = Color3.fromRGB(90, 60, 140),
	light = Color3.fromRGB(250, 230, 120),
	white = Color3.fromRGB(240, 240, 240),
}

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = true
	for k, v in props do
		p[k] = v
	end
	return p
end

local function label(parent, text, offsetY, color)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(8, 2)
	bb.StudsOffset = Vector3.new(0, offsetY or 6, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 80
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextColor3 = color or PALETTE.white
	tl.TextStrokeTransparency = 0
	tl.TextStrokeColor3 = Color3.new(0, 0, 0)
	tl.Font = Enum.Font.Arcade
	tl.TextScaled = true
	tl.Parent = bb
	bb.Parent = parent
	return bb
end

local function station(folder, opts)
	-- opts: { name, screen, position, color, action }
	local model = Instance.new("Model")
	model.Name = opts.name
	local base = part({
		Name = "Pad",
		Size = Vector3.new(12, 1, 12),
		Position = opts.position + Vector3.new(0, 0.5, 0),
		Color = PALETTE.stone,
	})
	base.Parent = model
	local trim = part({
		Name = "Trim",
		Size = Vector3.new(13, 0.6, 13),
		Position = opts.position + Vector3.new(0, 0.3, 0),
		Color = PALETTE.stoneDark,
	})
	trim.Parent = model
	local pillar = part({
		Name = "Marker",
		Size = Vector3.new(3, 6, 3),
		Position = opts.position + Vector3.new(0, 4, 0),
		Color = opts.color,
	})
	pillar.Parent = model
	local top = part({
		Name = "Top",
		Size = Vector3.new(4, 1.5, 4),
		Position = opts.position + Vector3.new(0, 7.5, 0),
		Color = opts.color,
		Material = Enum.Material.Neon,
	})
	top.Parent = model
	pillar:SetAttribute("Screen", opts.screen)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = opts.action or "Open"
	prompt.ObjectText = opts.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = pillar
	label(pillar, opts.name, 6, opts.color)
	model.PrimaryPart = base
	model.Parent = folder
	return model
end

local function tree(folder, position, scale)
	scale = scale or 1
	local trunk = part({
		Size = Vector3.new(2, 6, 2) * scale,
		Position = position + Vector3.new(0, 3 * scale, 0),
		Color = PALETTE.wood,
	})
	trunk.Parent = folder
	for i, size in { 8, 6, 4 } do
		local leaves = part({
			Size = Vector3.new(size, 3, size) * scale,
			Position = position + Vector3.new(0, (6 + (i - 1) * 2.6) * scale, 0),
			Color = PALETTE.leaf,
		})
		leaves.Parent = folder
	end
end

function WorldBuilder.Build()
	if Workspace:FindFirstChild("Hub") then
		return Workspace.Hub
	end
	local hub = Instance.new("Folder")
	hub.Name = "Hub"

	-- ground: a checker of two greens, voxel look
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = hub
	local TILE = 20
	for x = -6, 5 do
		for z = -6, 5 do
			local tile = part({
				Size = Vector3.new(TILE, 2, TILE),
				Position = Vector3.new(x * TILE + TILE / 2, -1, z * TILE + TILE / 2),
				Color = (x + z) % 2 == 0 and PALETTE.grass or PALETTE.grassDark,
			})
			tile.Parent = ground
		end
	end
	-- plaza
	local plaza = part({
		Size = Vector3.new(30, 0.4, 30),
		Position = Vector3.new(0, 0.2, 0),
		Color = PALETTE.stone,
	})
	plaza.Parent = hub
	local plazaTrim = part({
		Size = Vector3.new(32, 0.2, 32),
		Position = Vector3.new(0, 0.1, 0),
		Color = PALETTE.stoneDark,
	})
	plazaTrim.Parent = hub

	local spawn = Instance.new("SpawnLocation")
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = Vector3.new(0, 0.9, 6)
	spawn.Anchored = true
	spawn.Color = PALETTE.light
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = hub

	-- stations
	local stations = Instance.new("Folder")
	stations.Name = "Stations"
	stations.Parent = hub
	station(stations, {
		name = "Battle Gate",
		screen = "Stages",
		position = Vector3.new(0, 0, -40),
		color = PALETTE.fire,
		action = "Enter",
	})
	station(stations, {
		name = "Hatchery",
		screen = "Hatch",
		position = Vector3.new(-40, 0, 0),
		color = PALETTE.light,
		action = "Hatch",
	})
	station(stations, {
		name = "Camp",
		screen = "Camp",
		position = Vector3.new(40, 0, 0),
		color = PALETTE.wood,
		action = "Manage",
	})
	station(stations, {
		name = "Expedition Portal",
		screen = "Expedition",
		position = Vector3.new(0, 0, 44),
		color = PALETTE.dark,
		action = "Enter",
	})
	station(stations, {
		name = "Arena",
		screen = "Arena",
		position = Vector3.new(-40, 0, -40),
		color = PALETTE.water,
		action = "Fight",
	})
	station(stations, {
		name = "Codex",
		screen = "Codex",
		position = Vector3.new(40, 0, -40),
		color = PALETTE.leaf,
		action = "Browse",
	})
	station(stations, {
		name = "Shop",
		screen = "Shop",
		position = Vector3.new(-40, 0, 44),
		color = PALETTE.white,
		action = "Browse",
	})
	station(stations, {
		name = "Quest Board",
		screen = "Quests",
		position = Vector3.new(40, 0, 44),
		color = PALETTE.stone,
		action = "Read",
	})
	station(stations, {
		name = "Prestige Altar",
		screen = "Prestige",
		position = Vector3.new(70, 0, 0),
		color = PALETTE.dark,
		action = "Pray",
	})

	-- decoration
	local deco = Instance.new("Folder")
	deco.Name = "Deco"
	deco.Parent = hub
	local rng = Random.new(7)
	for _ = 1, 26 do
		local x, z = rng:NextInteger(-110, 110), rng:NextInteger(-110, 110)
		if math.abs(x) > 55 or math.abs(z) > 58 then
			tree(deco, Vector3.new(x, 0, z), rng:NextNumber(0.8, 1.4))
		end
	end
	-- pond
	local pond = part({
		Size = Vector3.new(24, 0.6, 18),
		Position = Vector3.new(-80, 0.1, 60),
		Color = PALETTE.water,
		Material = Enum.Material.Glass,
		Transparency = 0.2,
	})
	pond.Parent = deco

	hub.Parent = Workspace

	-- lighting: bright, saturated, low-shadow voxel look
	Lighting.ClockTime = 13
	Lighting.Brightness = 2.5
	Lighting.Ambient = Color3.fromRGB(120, 120, 130)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.2
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Color = Color3.fromRGB(199, 210, 255)
		atmosphere.Parent = Lighting
	end
	return hub
end

return WorldBuilder
