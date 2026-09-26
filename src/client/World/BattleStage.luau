--!nonstrict
-- Client battle playback: replays the server's event log on a floating stage with blocky pets,
-- floating numbers, HP callbacks and speed/skip controls. Purely cosmetic: outcome is final.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Skills = require(Shared.Config.Skills)
local Factory = require(script.Parent.PetModelFactory)
local Theme = require(script.Parent.Parent.UI.PixelTheme)

local BattleStage = {}

local ORIGIN = Vector3.new(0, 300, 0)
local SPOT = { A = Vector3.new(-7, 0, 0), B = Vector3.new(7, 0, 0) }
local stageFolder = nil
local active = nil -- current playback controller

local function ensureStage()
	if stageFolder and stageFolder.Parent then
		return stageFolder
	end
	stageFolder = Instance.new("Folder")
	stageFolder.Name = "BattleStage"
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(44, 2, 26)
	floor.Position = ORIGIN - Vector3.new(0, 1, 0)
	floor.Color = Color3.fromRGB(80, 84, 100)
	floor.Material = Enum.Material.SmoothPlastic
	floor.Parent = stageFolder
	for i = 1, 2 do
		local ring = Instance.new("Part")
		ring.Anchored = true
		ring.Size = Vector3.new(10, 0.3, 10)
		ring.Position = ORIGIN + (i == 1 and SPOT.A or SPOT.B) + Vector3.new(0, 0.15, 0)
		ring.Color = i == 1 and Theme.Colors.good or Theme.Colors.bad
		ring.Material = Enum.Material.SmoothPlastic
		ring.Parent = stageFolder
	end
	local back = Instance.new("Part")
	back.Anchored = true
	back.Size = Vector3.new(44, 18, 2)
	back.Position = ORIGIN + Vector3.new(0, 8, 14)
	back.Color = Color3.fromRGB(40, 44, 66)
	back.Material = Enum.Material.SmoothPlastic
	back.Parent = stageFolder
	stageFolder.Parent = Workspace
	return stageFolder
end

local function floatText(position: Vector3, text: string, color: Color3, size: number?)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Position = position
	holder.Parent = stageFolder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 40)
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

local function lunge(model, towards: Vector3)
	if not model or not model.PrimaryPart then
		return
	end
	local from = model:GetPivot()
	local dir = (towards - from.Position) * Vector3.new(1, 0, 1)
	if dir.Magnitude < 0.01 then
		return
	end
	local to = from + dir.Unit * 2
	task.spawn(function()
		model:PivotTo(to)
		task.wait(0.08)
		if model.Parent then
			model:PivotTo(from)
		end
	end)
end

local function flash(model, color)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Eye" and p.Name ~= "EyeWhite" then
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

-- payload: BattleResult payload from the server. opts: { speed, onHp(uid, hp, shield), onLog(text, kind), onFinished() }
function BattleStage.play(payload, opts)
	BattleStage.stop()
	ensureStage()
	local ctl = { speed = opts.speed or 1, finished = false }
	local models = {}
	local info = {} -- uid -> { maxHp, hp, shield, side, name }

	for _, c in payload.teamA do
		local cf = CFrame.new(ORIGIN + SPOT.A + Vector3.new(0, 0, (c.slot - 1) * 4))
			* CFrame.Angles(0, -math.pi / 2, 0)
		models[c.uid] = Factory.build(c.petId, c.variant, cf, 1)
		models[c.uid].Parent = stageFolder
		info[c.uid] =
			{ maxHp = c.maxHp, hp = c.hp, shield = 0, side = "A", name = c.name, petId = c.petId }
	end
	for _, c in payload.teamB do
		local cf = CFrame.new(ORIGIN + SPOT.B + Vector3.new(0, 0, (c.slot - 1) * 4))
			* CFrame.Angles(0, math.pi / 2, 0)
		models[c.uid] = Factory.build(c.petId, c.variant, cf, 1)
		models[c.uid].Parent = stageFolder
		info[c.uid] =
			{ maxHp = c.maxHp, hp = c.hp, shield = 0, side = "B", name = c.name, petId = c.petId }
	end

	local camera = Workspace.CurrentCamera
	local prevType = camera.CameraType
	local prevCFrame = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(ORIGIN + Vector3.new(0, 9, -24), ORIGIN + Vector3.new(0, 2.5, 0))

	local function headPos(uid)
		local m = models[uid]
		if not m then
			return ORIGIN
		end
		return m:GetPivot().Position + Vector3.new(0, (m:GetAttribute("Height") or 3) + 0.5, 0)
	end

	local function apply(ev)
		local t = ev.type
		if t == "Damage" then
			local i = info[ev.dst]
			if i then
				i.hp = ev.hp
				if ev.absorbed and ev.absorbed > 0 then
					i.shield = math.max(0, i.shield - ev.absorbed)
				end
			end
			if ev.src and models[ev.src] then
				lunge(
					models[ev.src],
					models[ev.dst] and models[ev.dst]:GetPivot().Position or ORIGIN
				)
			end
			if models[ev.dst] then
				flash(models[ev.dst], Color3.new(1, 1, 1))
			end
			local color = ev.crit and Theme.Colors.accent
				or (ev.status and Theme.Colors.essence or Theme.Colors.text)
			local text = tostring(ev.amount)
			if ev.crit then
				text = text .. "!"
			end
			if ev.interrupt then
				text = "INTERRUPT " .. text
			end
			floatText(headPos(ev.dst), text, color, ev.crit and 22 or 16)
			if opts.onHp and i then
				opts.onHp(ev.dst, i.hp, i.shield)
			end
		elseif t == "Heal" then
			local i = info[ev.dst]
			if i then
				i.hp = ev.hp
			end
			floatText(headPos(ev.dst), "+" .. tostring(ev.amount), Theme.Colors.good)
			if opts.onHp and i then
				opts.onHp(ev.dst, i.hp, i.shield)
			end
		elseif t == "Shield" then
			local i = info[ev.dst]
			if i then
				i.shield = ev.total
			end
			floatText(headPos(ev.dst), "Shield " .. tostring(ev.amount), Theme.Colors.shield)
			if opts.onHp and i then
				opts.onHp(ev.dst, i.hp, i.shield)
			end
		elseif t == "ShieldExpired" then
			local i = info[ev.dst]
			if i then
				i.shield = 0
				if opts.onHp then
					opts.onHp(ev.dst, i.hp, 0)
				end
			end
		elseif t == "Skill" then
			local skill = Skills[ev.skill]
			floatText(
				headPos(ev.src) + Vector3.new(0, 1, 0),
				skill and skill.displayName or ev.skill,
				Theme.Colors.accent,
				16
			)
			if models[ev.src] then
				flash(models[ev.src], Theme.Colors.accent)
			end
			if opts.onLog then
				opts.onLog(
					string.format(
						"%s used %s",
						info[ev.src] and info[ev.src].name or "?",
						skill and skill.displayName or ev.skill
					),
					"skill"
				)
			end
		elseif t == "Interrupt" then
			floatText(headPos(ev.dst) + Vector3.new(0, 1, 0), "INTERRUPTED", Theme.Colors.bad, 16)
			if opts.onLog then
				opts.onLog(
					string.format("%s interrupted %s!", info[ev.src].name, info[ev.dst].name),
					"good"
				)
			end
		elseif t == "Status" then
			floatText(
				headPos(ev.dst) + Vector3.new(0, 0.6, 0),
				ev.status .. (ev.stacks and ev.stacks > 1 and (" x" .. ev.stacks) or ""),
				Theme.Colors.essence,
				13
			)
		elseif t == "Immune" then
			floatText(headPos(ev.dst) + Vector3.new(0, 0.6, 0), "IMMUNE", Theme.Colors.textDim, 13)
		elseif t == "Miss" then
			floatText(headPos(ev.dst), "MISS", Theme.Colors.textDim, 14)
		elseif t == "Revive" then
			local i = info[ev.dst]
			if i then
				i.hp = ev.hp
			end
			floatText(headPos(ev.dst), "SECOND DAWN", Theme.Colors.accent, 16)
			if models[ev.dst] then
				models[ev.dst]:PivotTo(models[ev.dst]:GetPivot() + Vector3.new(0, 3, 0))
			end
			if opts.onHp and i then
				opts.onHp(ev.dst, i.hp, i.shield)
			end
		elseif t == "Death" then
			local m = models[ev.dst]
			if m then
				TweenService:Create(m.PrimaryPart, TweenInfo.new(0.4), { Transparency = 0.6 })
					:Play()
				m:PivotTo(m:GetPivot() * CFrame.Angles(0, 0, math.rad(80)) - Vector3.new(0, 1, 0))
			end
			if opts.onLog then
				opts.onLog(
					string.format("%s was defeated", info[ev.dst] and info[ev.dst].name or "?"),
					"bad"
				)
			end
		elseif t == "BattleEnd" then
			ctl.finished = true
		end
	end

	local events = payload.events
	local index = 1
	local elapsed = 0
	local lastTime = os.clock()
	ctl.connection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		elapsed += (now - lastTime) * ctl.speed
		lastTime = now
		while index <= #events and events[index].t <= elapsed do
			apply(events[index])
			index += 1
		end
		if index > #events and not ctl.finished then
			ctl.finished = true
		end
		if ctl.finished and not ctl.done then
			ctl.done = true
			task.delay(0.8 / ctl.speed, function()
				if active == ctl and opts.onFinished then
					opts.onFinished()
				end
			end)
		end
	end)

	function ctl.setSpeed(speed: number)
		ctl.speed = speed
	end

	function ctl.skip()
		while index <= #events do
			local ev = events[index]
			-- apply state-only effects instantly without effects spam
			if ev.type == "Damage" or ev.type == "Heal" or ev.type == "Revive" then
				local i = info[ev.dst]
				if i then
					i.hp = ev.hp
				end
			elseif ev.type == "Shield" then
				local i = info[ev.dst]
				if i then
					i.shield = ev.total
				end
			elseif ev.type == "Death" then
				local m = models[ev.dst]
				if m then
					m:PivotTo(
						m:GetPivot() * CFrame.Angles(0, 0, math.rad(80)) - Vector3.new(0, 1, 0)
					)
				end
			end
			index += 1
		end
		for uid, i in info do
			if opts.onHp then
				opts.onHp(uid, i.hp, i.shield)
			end
		end
		ctl.finished = true
	end

	function ctl.stop()
		if ctl.connection then
			ctl.connection:Disconnect()
			ctl.connection = nil
		end
		for _, m in models do
			m:Destroy()
		end
		if camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = prevType
			camera.CFrame = prevCFrame
		end
		if active == ctl then
			active = nil
		end
	end

	active = ctl
	return ctl
end

function BattleStage.stop()
	if active then
		active.stop()
	end
end

return BattleStage
