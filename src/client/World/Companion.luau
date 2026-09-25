--!nonstrict
-- Shows the local player's active team pet following behind the character (client-side only).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Factory = require(script.Parent.PetModelFactory)

local Companion = {}
local player = Players.LocalPlayer
local model = nil
local currentKey = nil
local folder = nil
local hidden = false
local connection = nil

local FOLLOW_OFFSET = Vector3.new(-3, 0, 3)
local BOB_SPEED = 3

local function ensureFolder()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "LocalCompanion"
		folder.Parent = Workspace
	end
	return folder
end

local function destroy()
	if model then
		model:Destroy()
		model = nil
	end
	currentKey = nil
end

local function step(dt)
	if not model or hidden then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local target = root.CFrame * CFrame.new(FOLLOW_OFFSET)
	local pos = target.Position
	pos = Vector3.new(pos.X, root.Position.Y - 1.6 + math.sin(os.clock() * BOB_SPEED) * 0.2, pos.Z)
	local look = CFrame.lookAt(pos, Vector3.new(root.Position.X, pos.Y, root.Position.Z))
	local alpha = math.clamp(dt * 6, 0, 1)
	model:PivotTo(model:GetPivot():Lerp(look, alpha))
end

-- inst: pet instance table from the profile (or nil to remove)
function Companion.set(inst)
	if not inst then
		destroy()
		return
	end
	local key = inst.petId .. ":" .. (inst.variant or "Normal")
	if key == currentKey and model and model.Parent then
		return
	end
	destroy()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local origin = root and (root.CFrame * CFrame.new(FOLLOW_OFFSET)) or CFrame.new(0, 3, 0)
	model = Factory.build(inst.petId, inst.variant, origin, 0.8)
	model.Name = "Companion"
	model.Parent = ensureFolder()
	currentKey = key
	if not connection then
		connection = RunService.Heartbeat:Connect(step)
	end
end

function Companion.setHidden(value: boolean)
	hidden = value
	if model then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency = value and 1 or 0
			end
		end
	end
end

return Companion
