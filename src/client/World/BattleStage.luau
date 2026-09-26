--!nonstrict
-- Battle playback controller: replays the server's event log as a "voxel clash" (斗蛐蛐-style)
-- side-view fight — pets slide in, dash into each other with knockback, leap-cast skills, and
-- shatter into voxels on KO with a beat of slow motion. Purely cosmetic: outcome is final.
-- Stage, effects and sounds live in BattleFx.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Skills = require(Shared.Config.Skills)
local Factory = require(script.Parent.PetModelFactory)
local Fx = require(script.Parent.BattleFx)
local Theme = require(script.Parent.Parent.UI.PixelTheme)

local BattleStage = {}

local ORIGIN = Fx.ORIGIN
local HOME = Fx.HOME
local YAW = { A = -math.pi / 2, B = math.pi / 2 } -- face down the lane toward the foe
local active = nil -- current playback controller

-- payload: BattleResult payload from the server. opts: { speed, onHp(uid, hp, shield), onLog(text, kind), onFinished() }
function BattleStage.play(payload, opts)
	BattleStage.stop()
	Fx.ensureStage()
	local ctl = { speed = opts.speed or 1, finished = false, slowUntil = 0 }
	local models, plates, info, homeCF = {}, {}, {}, {}
	local moves = {} -- { model, from, to, t0, dur, arc, spin, onDone }
	local shake, fovKick = 0, 0
	local rng = Random.new()

	-- tiny per-frame movement scheduler (smoothstep, optional hop arc / spin); a new move for
	-- a model cancels its current one, so overlapping attacks never fight over a pivot
	local function move(model, to: CFrame, dur: number, arc: number?, spin: number?, onDone)
		for i = #moves, 1, -1 do
			if moves[i].model == model then
				table.remove(moves, i)
			end
		end
		if not model.Parent then
			return
		end
		table.insert(moves, {
			model = model,
			from = model:GetPivot(),
			to = to,
			t0 = os.clock(),
			dur = math.max(0.01, dur),
			arc = arc or 0,
			spin = spin or 0,
			onDone = onDone,
		})
	end

	local function dropMoves(model)
		for i = #moves, 1, -1 do
			if moves[i].model == model then
				table.remove(moves, i)
			end
		end
	end

	local function stepMoves(now)
		for i = #moves, 1, -1 do
			local m = moves[i]
			local a = math.clamp((now - m.t0) / m.dur, 0, 1)
			local e = a * a * (3 - 2 * a)
			local cf = m.from:Lerp(m.to, e)
			if m.arc > 0 then
				cf += Vector3.new(0, math.sin(a * math.pi) * m.arc, 0)
			end
			if m.spin ~= 0 then
				cf *= CFrame.Angles(0, 0, math.sin(a * math.pi) * m.spin)
			end
			if m.model.Parent then
				m.model:PivotTo(cf)
			end
			if a >= 1 then
				table.remove(moves, i)
				if m.onDone then
					m.onDone()
				end
			end
		end
	end

	local function headPos(uid)
		local m = models[uid]
		if not m then
			return ORIGIN
		end
		return m:GetPivot().Position + Vector3.new(0, (m:GetAttribute("Height") or 3) + 0.5, 0)
	end

	local function pushHp(uid)
		local i = info[uid]
		if opts.onHp and i then
			opts.onHp(uid, i.hp, i.shield)
		end
		if plates[uid] and i then
			plates[uid].set(i.hp, i.maxHp, i.shield)
		end
	end

	-- impact: cubes + knockback + camera shake, shared by melee hits and skill slams
	local function impact(srcUid, dstUid, big: boolean, color: Color3)
		local victim = models[dstUid]
		if not victim or not info[srcUid] then
			return
		end
		local toward = if info[srcUid].side == "A" then 1 else -1
		local mid = victim:GetPivot().Position + Vector3.new(toward * 1.2, 1.6, 0)
		Fx.burst(mid, color, if big then 16 else 8, if big then 5 else 3)
		if big then
			Fx.shockwave(Vector3.new(mid.X, ORIGIN.Y, mid.Z), color)
			shake = math.max(shake, 1.4)
			fovKick = -7
			Fx.sfx("heavy")
		else
			shake = math.max(shake, 0.6)
			Fx.sfx("clash")
		end
		Fx.flash(victim, Color3.new(1, 1, 1))
		move(
			victim,
			victim:GetPivot() + Vector3.new(toward * (if big then 3 else 1.4), 0, 0),
			0.14,
			if big then 0.7 else 0.25
		)
		task.delay(0.18 / ctl.speed, function()
			if victim.Parent then
				move(victim, homeCF[dstUid], 0.3)
			end
		end)
	end

	local lastSkill = {} -- uid -> clock of their last leap; the matching Damage skips its own dash

	local function apply(ev)
		local t = ev.type
		if t == "BattleStart" then
			for uid, m in models do
				local away = homeCF[uid] * CFrame.new(if info[uid].side == "A" then -8 else 8, 0, 0)
				m:PivotTo(away)
				move(m, homeCF[uid], 0.5)
			end
			Fx.floatText(ORIGIN + Vector3.new(0, 4, 0), "VS", Theme.Colors.accent, 28)
			Fx.sfx("swoosh", 0.8)
		elseif t == "Damage" then
			local i = info[ev.dst]
			if i then
				i.hp = ev.hp
				if ev.absorbed and ev.absorbed > 0 then
					i.shield = math.max(0, i.shield - ev.absorbed)
				end
			end
			local attacker = ev.src and models[ev.src] or nil
			if attacker and info[ev.src] then
				local skilled = (os.clock() - (lastSkill[ev.src] or 0)) < 0.5
				if not skilled then -- a skill leap has already closed the distance
					local victim = models[ev.dst]
					if victim then
						local toward = if info[ev.src].side == "A" then 2.6 else -2.6
						move(
							attacker,
							victim:GetPivot() + Vector3.new(toward, 0, 0),
							0.12,
							0.5,
							nil,
							function()
								impact(
									ev.src,
									ev.dst,
									ev.crit == true,
									Fx.elementColor(info[ev.src].petId)
								)
								task.delay(0.1 / ctl.speed, function()
									if attacker.Parent then
										move(attacker, homeCF[ev.src], 0.28)
									end
								end)
							end
						)
					end
				else
					impact(ev.src, ev.dst, ev.crit == true, Fx.elementColor(info[ev.src].petId))
				end
			end
			local color = ev.crit and Theme.Colors.accent
				or (ev.status and Theme.Colors.essence or Theme.Colors.text)
			local text = tostring(ev.amount)
			if ev.crit then
				text = text .. "!"
				Fx.sfx("ping", 1.25)
			end
			if ev.interrupt then
				text = "INTERRUPT " .. text
			end
			Fx.floatText(headPos(ev.dst), text, color, ev.crit and 22 or 16)
			pushHp(ev.dst)
		elseif t == "Skill" then
			local skill = Skills[ev.skill]
			local caster = models[ev.src]
			lastSkill[ev.src] = os.clock()
			Fx.floatText(
				headPos(ev.src) + Vector3.new(0, 1, 0),
				skill and skill.displayName or ev.skill,
				Theme.Colors.accent,
				16
			)
			if caster and info[ev.src] then
				local color = Fx.elementColor(info[ev.src].petId)
				Fx.flash(caster, color)
				Fx.burst(caster:GetPivot().Position + Vector3.new(0, 1, 0), color, 6, 2)
				Fx.sfx("swoosh")
				local victim = models[ev.dst]
				if victim then
					local toward = if info[ev.src].side == "A" then 2.2 else -2.2
					local contact = victim:GetPivot() + Vector3.new(toward, 0, 0)
					local spin = if info[ev.src].side == "A" then -math.pi * 2 else math.pi * 2
					move(caster, contact, 0.24, 2.4, spin, function()
						impact(ev.src, ev.dst, true, color)
						Fx.sfx("land")
						task.delay(0.15 / ctl.speed, function()
							if caster.Parent then
								move(caster, homeCF[ev.src], 0.32)
							end
						end)
					end)
				end
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
			Fx.floatText(
				headPos(ev.dst) + Vector3.new(0, 1, 0),
				"INTERRUPTED",
				Theme.Colors.bad,
				16
			)
			Fx.burst(headPos(ev.dst), Theme.Colors.accent, 8, 3)
			Fx.sfx("ping", 0.7)
			if opts.onLog then
				opts.onLog(
					string.format("%s interrupted %s!", info[ev.src].name, info[ev.dst].name),
					"good"
				)
			end
		elseif t == "Heal" then
			local i = info[ev.dst]
			if i then
				i.hp = ev.hp
			end
			Fx.floatText(headPos(ev.dst), "+" .. tostring(ev.amount), Theme.Colors.good)
			Fx.burst(headPos(ev.dst) - Vector3.new(0, 1, 0), Theme.Colors.good, 6, 2)
			pushHp(ev.dst)
		elseif t == "Shield" then
			local i = info[ev.dst]
			if i then
				i.shield = ev.total
			end
			Fx.floatText(headPos(ev.dst), "Shield " .. tostring(ev.amount), Theme.Colors.shield)
			Fx.burst(headPos(ev.dst) - Vector3.new(0, 1, 0), Theme.Colors.info, 8, 2)
			pushHp(ev.dst)
		elseif t == "ShieldExpired" then
			local i = info[ev.dst]
			if i then
				i.shield = 0
				pushHp(ev.dst)
			end
		elseif t == "Status" then
			Fx.floatText(
				headPos(ev.dst) + Vector3.new(0, 0.6, 0),
				ev.status .. (ev.stacks and ev.stacks > 1 and (" x" .. ev.stacks) or ""),
				Theme.Colors.essence,
				13
			)
		elseif t == "Immune" then
			Fx.floatText(
				headPos(ev.dst) + Vector3.new(0, 0.6, 0),
				"IMMUNE",
				Theme.Colors.textDim,
				13
			)
		elseif t == "Miss" then
			local victim = models[ev.dst]
			if victim then -- sidestep dodge, then back to the spot
				local back = if info[ev.src] and info[ev.src].side == "A" then 1.4 else -1.4
				move(victim, victim:GetPivot() + Vector3.new(back, 0, 0.8), 0.12, 0.3)
				task.delay(0.2 / ctl.speed, function()
					if victim.Parent then
						move(victim, homeCF[ev.dst], 0.25)
					end
				end)
			end
			Fx.floatText(headPos(ev.dst), "MISS", Theme.Colors.textDim, 14)
		elseif t == "Revive" then
			local i = info[ev.dst]
			if i then
				i.hp = ev.hp
			end
			local m = models[ev.dst]
			if m then
				move(m, m:GetPivot() + Vector3.new(0, 2.5, 0), 0.3, 1.2)
				Fx.burst(m:GetPivot().Position, Theme.Colors.borderLight, 14, 4)
			end
			Fx.floatText(headPos(ev.dst), "SECOND DAWN", Theme.Colors.accent, 16)
			Fx.sfx("ping", 1.5)
			pushHp(ev.dst)
		elseif t == "Death" then
			local m = models[ev.dst]
			if m then
				ctl.slowUntil = os.clock() + 0.55 -- a beat of slow motion for the KO
				shake = math.max(shake, 1.8)
				Fx.sfx("ko")
				local center = m:GetPivot().Position
				Fx.burst(
					center + Vector3.new(0, 1.5, 0),
					Fx.elementColor(info[ev.dst].petId),
					18,
					5
				)
				Fx.shockwave(Vector3.new(center.X, ORIGIN.Y, center.Z), Theme.Colors.accent)
				dropMoves(m)
				for _, p in m:GetDescendants() do -- the body breaks into its voxels
					if p:IsA("BasePart") and p.Name ~= "Nameplate" then
						local dir = (p.Position - center)
							+ Vector3.new(rng:NextNumber(-1, 1), 1.5, rng:NextNumber(-0.4, 0.4))
						local dest = p.CFrame
							+ dir.Unit * (2.5 + rng:NextNumber() * 3)
							- Vector3.new(0, 2.5, 0)
						TweenService:Create(
							p,
							TweenInfo.new(
								0.7 + rng:NextNumber() * 0.3,
								Enum.EasingStyle.Quad,
								Enum.EasingDirection.In
							),
							{ CFrame = dest, Transparency = 1 }
						):Play()
					end
				end
				task.delay(1.4 / ctl.speed, function()
					m:Destroy()
				end)
			end
			if opts.onLog then
				opts.onLog(
					string.format("%s was defeated", info[ev.dst] and info[ev.dst].name or "?"),
					"bad"
				)
			end
		elseif t == "BattleEnd" then
			local winnerUid = nil
			for uid, i in info do
				if i.hp > 0 then
					winnerUid = uid
					break
				end
			end
			if winnerUid and models[winnerUid] then -- victory hop + confetti
				local m = models[winnerUid]
				task.delay(0.35 / ctl.speed, function()
					if m.Parent then
						move(m, m:GetPivot() + Vector3.new(0, 1.6, 0), 0.22, 1.6)
						task.delay(0.24, function()
							if m.Parent then
								move(m, homeCF[winnerUid], 0.24)
							end
						end)
					end
					Fx.burst(
						m:GetPivot().Position + Vector3.new(0, 2.5, 0),
						Theme.Colors.accent,
						16,
						4
					)
					Fx.burst(
						m:GetPivot().Position + Vector3.new(0, 2.5, 0),
						Fx.elementColor(info[winnerUid].petId),
						12,
						4
					)
					Fx.sfx("ping", 1.4)
				end)
			end
			ctl.finished = true
		end
	end

	for _, c in payload.teamA do
		local cf = CFrame.new(ORIGIN + HOME.A + Vector3.new(0, 0, (c.slot - 1) * 4))
			* CFrame.Angles(0, YAW.A, 0)
		models[c.uid] = Factory.build(c.petId, c.variant, cf, 1)
		models[c.uid].Parent = Fx.ensureStage()
		info[c.uid] =
			{ maxHp = c.maxHp, hp = c.hp, shield = 0, side = "A", name = c.name, petId = c.petId }
		homeCF[c.uid] = cf
	end
	for _, c in payload.teamB do
		local cf = CFrame.new(ORIGIN + HOME.B + Vector3.new(0, 0, (c.slot - 1) * 4))
			* CFrame.Angles(0, YAW.B, 0)
		models[c.uid] = Factory.build(c.petId, c.variant, cf, 1)
		models[c.uid].Parent = Fx.ensureStage()
		info[c.uid] =
			{ maxHp = c.maxHp, hp = c.hp, shield = 0, side = "B", name = c.name, petId = c.petId }
		homeCF[c.uid] = cf
	end
	for uid, m in models do
		plates[uid] = Fx.makeNameplate(m, info[uid].side, info[uid].name)
		plates[uid].set(info[uid].hp, info[uid].maxHp, 0)
	end

	local camera = Workspace.CurrentCamera
	local prevType, prevCFrame = camera.CameraType, camera.CFrame
	local prevFov = camera.FieldOfView
	local baseCF = CFrame.lookAt(ORIGIN + Vector3.new(0, 6.5, -26), ORIGIN + Vector3.new(0, 3, 0))
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = baseCF

	local events = payload.events
	local index = 1
	local elapsed = 0
	local lastTime = os.clock()
	ctl.connection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local slow = if now < ctl.slowUntil then 0.3 else 1
		elapsed += (now - lastTime) * ctl.speed * slow
		lastTime = now
		stepMoves(now)
		while index <= #events and events[index].t <= elapsed do
			local ev = events[index]
			index += 1 -- advance first: a throwing event must not replay (and error) every frame
			local ok, err = pcall(apply, ev)
			if not ok and not ctl.applyWarned then
				ctl.applyWarned = true
				warn("[BattleStage] event " .. tostring(ev.type) .. " failed: " .. tostring(err))
			end
		end
		-- camera shake / fov punch decays back to the framing shot
		if shake > 0.001 or fovKick < -0.01 then
			shake *= 0.86
			fovKick *= 0.82
			camera.CFrame = baseCF
				* CFrame.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, 0)
			camera.FieldOfView = 70 + fovKick
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
					m:Destroy()
				end
			end
			index += 1
		end
		moves = {}
		for uid in info do
			if models[uid] and models[uid].Parent then
				models[uid]:PivotTo(homeCF[uid])
			end
			pushHp(uid)
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
			camera.FieldOfView = prevFov
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
