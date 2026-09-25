--!nonstrict
-- Blocky placeholder pets built from Parts (client-side only). Shape by role, colors by element,
-- deterministic per-species hue shift, variant tints. Replaced by real voxel meshes later (CA-04).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pets = require(ReplicatedStorage.Shared.Config.Pets)
local Theme = require(script.Parent.Parent.UI.PixelTheme)

local Factory = {}

local function hash(str: string): number
	local h = 0
	for i = 1, #str do
		h = (h * 31 + string.byte(str, i)) % 2147483647
	end
	return h
end

local function shift(color: Color3, hueDelta: number, satMult: number, valMult: number)
	local h, s, v = color:ToHSV()
	h = (h + hueDelta) % 1
	return Color3.fromHSV(h, math.clamp(s * satMult, 0, 1), math.clamp(v * valMult, 0, 1))
end

local function part(model, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = true
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Parent = model
	return p
end

function Factory.palette(petId: string, variant: string?)
	local def = Pets[petId]
	local base = Theme.Element[def.element] or Theme.Element.Neutral
	local h = hash(petId)
	local body = shift(base, ((h % 20) - 10) / 200, 1, 1)
	local accent = shift(base, 0.12 + (h % 7) / 100, 1.1, 1.15)
	local belly = shift(base, 0, 0.35, 1.35)
	local eye = Color3.fromRGB(20, 20, 30)
	local material = Enum.Material.SmoothPlastic
	if variant == "Golden" then
		body = Color3.fromRGB(255, 200, 60)
		accent = Color3.fromRGB(255, 240, 150)
		belly = Color3.fromRGB(255, 225, 120)
		material = Enum.Material.Metal
	elseif variant == "Rainbow" then
		body = Color3.fromHSV((h % 100) / 100, 0.8, 1)
		accent = Color3.fromHSV(((h % 100) / 100 + 0.33) % 1, 0.8, 1)
		belly = Color3.fromHSV(((h % 100) / 100 + 0.66) % 1, 0.6, 1)
		material = Enum.Material.Neon
	elseif variant == "DarkMatter" then
		body = Color3.fromRGB(40, 20, 70)
		accent = Color3.fromRGB(160, 60, 255)
		belly = Color3.fromRGB(80, 40, 120)
		eye = Color3.fromRGB(200, 120, 255)
		material = Enum.Material.Neon
	end
	return { body = body, accent = accent, belly = belly, eye = eye, material = material }
end

-- Builds a pet model facing -Z, feet at y = 0 of `origin`. scale 1 = ~3 studs tall.
function Factory.build(petId: string, variant: string?, origin: CFrame, scale: number?)
	scale = scale or 1
	local def = Pets[petId]
	local pal = Factory.palette(petId, variant)
	local model = Instance.new("Model")
	model.Name = petId
	local s = scale
	local role = def.role

	-- body proportions by role
	local bodySize = Vector3.new(2.0, 1.5, 2.6)
	local headSize = Vector3.new(1.6, 1.4, 1.4)
	if role == "Tank" then
		bodySize = Vector3.new(2.6, 1.9, 2.8)
		headSize = Vector3.new(1.8, 1.4, 1.5)
	elseif role == "Attacker" then
		bodySize = Vector3.new(1.7, 1.4, 2.8)
		headSize = Vector3.new(1.5, 1.4, 1.5)
	elseif role == "Control" then
		bodySize = Vector3.new(1.8, 1.4, 2.2)
		headSize = Vector3.new(1.8, 1.6, 1.5)
	end
	local legH = 0.9
	local bodyY = legH + bodySize.Y / 2
	local body = part(
		model,
		"Body",
		bodySize * s,
		origin * CFrame.new(0, bodyY * s, 0),
		pal.body,
		pal.material
	)
	part(
		model,
		"Belly",
		Vector3.new(bodySize.X * 0.7, bodySize.Y * 0.5, 0.2) * s,
		origin * CFrame.new(0, (bodyY - 0.2) * s, -(bodySize.Z / 2) * s),
		pal.belly,
		pal.material
	)
	local headY = bodyY + bodySize.Y / 2 + headSize.Y / 2 - 0.3
	local headZ = -(bodySize.Z / 2) + headSize.Z / 2 - 0.4
	local head = part(
		model,
		"Head",
		headSize * s,
		origin * CFrame.new(0, headY * s, headZ * s),
		pal.body,
		pal.material
	)
	-- eyes
	for _, side in { -1, 1 } do
		part(
			model,
			"EyeWhite",
			Vector3.new(0.4, 0.4, 0.15) * s,
			origin * CFrame.new(side * 0.4 * s, (headY + 0.15) * s, (headZ - headSize.Z / 2) * s),
			Color3.new(1, 1, 1)
		)
		part(
			model,
			"Eye",
			Vector3.new(0.2, 0.25, 0.2) * s,
			origin
				* CFrame.new(
					side * 0.4 * s,
					(headY + 0.12) * s,
					(headZ - headSize.Z / 2 - 0.02) * s
				),
			pal.eye
		)
	end
	-- legs
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			part(
				model,
				"Leg",
				Vector3.new(0.55, legH, 0.55) * s,
				origin
					* CFrame.new(
						x * (bodySize.X / 2 - 0.35) * s,
						(legH / 2) * s,
						z * (bodySize.Z / 2 - 0.4) * s
					),
				pal.accent,
				pal.material
			)
		end
	end
	-- element / role decorations
	if def.element == "Fire" then
		part(
			model,
			"Flame",
			Vector3.new(0.5, 0.9, 0.5) * s,
			origin * CFrame.new(0, (bodyY + bodySize.Y / 2 + 0.3) * s, (bodySize.Z / 2 - 0.3) * s),
			Color3.fromRGB(255, 160, 40),
			Enum.Material.Neon
		)
	elseif def.element == "Water" then
		part(
			model,
			"Fin",
			Vector3.new(0.2, 0.9, 1.2) * s,
			origin * CFrame.new(0, (bodyY + bodySize.Y / 2 + 0.3) * s, 0),
			pal.accent,
			pal.material
		)
	elseif def.element == "Grass" then
		part(
			model,
			"Leaf",
			Vector3.new(0.9, 0.2, 0.9) * s,
			origin * CFrame.new(0, (headY + headSize.Y / 2 + 0.1) * s, headZ * s),
			Color3.fromRGB(70, 170, 70),
			pal.material
		)
	elseif def.element == "Dark" then
		for _, side in { -1, 1 } do
			part(
				model,
				"Horn",
				Vector3.new(0.3, 0.8, 0.3) * s,
				origin * CFrame.new(side * 0.5 * s, (headY + headSize.Y / 2 + 0.3) * s, headZ * s),
				pal.accent,
				pal.material
			)
		end
	elseif def.element == "Light" then
		part(
			model,
			"Halo",
			Vector3.new(1.4, 0.15, 1.4) * s,
			origin * CFrame.new(0, (headY + headSize.Y / 2 + 0.5) * s, headZ * s),
			Color3.fromRGB(255, 240, 150),
			Enum.Material.Neon
		)
	end
	for _, side in { -1, 1 } do
		part(
			model,
			"Ear",
			Vector3.new(0.4, 0.6, 0.3) * s,
			origin
				* CFrame.new(
					side * (headSize.X / 2 - 0.2) * s,
					(headY + headSize.Y / 2 + 0.2) * s,
					headZ * s
				),
			pal.accent,
			pal.material
		)
	end
	local tail = part(
		model,
		"Tail",
		Vector3.new(0.4, 0.4, 1.0) * s,
		origin * CFrame.new(0, (bodyY + 0.2) * s, (bodySize.Z / 2 + 0.4) * s),
		pal.accent,
		pal.material
	)
	local _ = tail
	model.PrimaryPart = body
	model:SetAttribute("PetId", petId)
	model:SetAttribute("Height", (headY + headSize.Y / 2 + 0.6) * s)
	model:SetAttribute("Head", head.Name)
	return model
end

return Factory
