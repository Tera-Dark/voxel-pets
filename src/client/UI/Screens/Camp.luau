--!nonstrict
-- Idle camp: assign pets to buildings, upgrade, collect. Pending amounts refresh every few seconds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Camp = require(Shared.Config.Camp)
local Formulas = require(Shared.Config.Formulas)

local Screen = {}
local ui = {}
local snapshot = nil
local ORDER = { "Mine", "Orchard", "Outpost" }

local function fetch(ctx)
	local ok, err, snap = ctx.Net.invoke("GetCamp")
	if ok then
		snapshot = snap
	else
		ctx.toast(err, "bad")
	end
end

local function refresh(ctx)
	local C, Theme, State, Net = ctx.C, ctx.Theme, ctx.State, ctx.Net
	if not snapshot then
		return
	end
	for _, child in ui.cards:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local p = State.profile
	for i, id in ORDER do
		local b = snapshot.buildings[id]
		local def = Camp.Buildings[id]
		local card = C.panel(
			{ Size = UDim2.fromOffset(268, 330), LayoutOrder = i, Parent = ui.cards },
			string.format("%s  Lv%d", b.displayName, b.level)
		)
		local y = 38
		local function line(text, color, h)
			C.label({
				Size = UDim2.new(1, -16, 0, h or 16),
				Position = UDim2.fromOffset(8, y),
				Text = text,
				TextSize = 9,
				TextColor3 = color or Theme.Colors.text,
				Parent = card,
			})
			y += (h or 16) + 2
		end
		if not b.unlocked then
			local u = def.unlock
			line("LOCKED", Theme.Colors.bad, 18)
			line(
				u.type == "StagesCleared" and ("Clear " .. u.count .. " stages to unlock")
					or "Unlock expeditions (clear 1-5)",
				Theme.Colors.textDim,
				30
			)
		else
			local affinity = {}
			for e in def.affinity do
				table.insert(affinity, e)
			end
			table.sort(affinity)
			line(
				string.format(
					"Produces: %s   Affinity: %s (+25%%)",
					def.produces,
					table.concat(affinity, "/")
				),
				Theme.Colors.textDim,
				28
			)
			line(string.format("Slots %d / %d", #b.workers, b.slots), Theme.Colors.text)
			for slot = 1, b.slots do
				local uid = b.workers[slot]
				local inst = uid and p.pets[uid]
				local text = inst and (State.petName(inst) .. " Lv" .. inst.level) or "+ assign pet"
				C.button({
					Size = UDim2.new(1, -16, 0, 24),
					Position = UDim2.fromOffset(8, y),
					Text = text,
					TextSize = 9,
					BackgroundColor3 = inst and Theme.Colors.panelLight or Theme.Colors.bg,
					Parent = card,
				}, function()
					if inst then
						local ok, err = Net.invoke("CampAssign", id, slot, nil)
						if not ok then
							ctx.toast(err, "bad")
						end
						fetch(ctx)
						refresh(ctx)
					else
						ctx.openPetPicker("Assign to " .. b.displayName, function(pickUid)
							return State.isBusy(pickUid) == nil
						end, function(pickUid)
							local ok, err = Net.invoke("CampAssign", id, slot, pickUid)
							if not ok then
								ctx.toast(err, "bad")
							end
							fetch(ctx)
							refresh(ctx)
						end)
					end
				end)
				y += 28
			end
			y = 250
			line(
				string.format(
					"Upgrade: %s coins (+15%% output, +1 slot / 5 lv)",
					Formulas.formatNumber(b.upgradeCost)
				),
				Theme.Colors.textDim,
				26
			)
			local up = C.button({
				Size = UDim2.new(1, -16, 0, 28),
				Position = UDim2.new(0, 8, 1, -36),
				Text = "Upgrade",
				BackgroundColor3 = Theme.Colors.info,
				TextSize = 10,
				Parent = card,
			}, function()
				local ok, err = Net.invoke("CampUpgrade", id)
				ctx.toast(ok and "Upgraded!" or err, ok and "good" or "bad")
				fetch(ctx)
				refresh(ctx)
			end)
			C.setEnabled(up, (p.coins or 0) >= b.upgradeCost)
		end
	end
	ui.summary.Text = string.format(
		"Pending: %s coins, %d tickets   |   Rate: %s coins/h, %.2f tickets/h   |   Offline cap %dh%s",
		Formulas.formatNumber(snapshot.pending.coins),
		math.floor(snapshot.pending.tickets),
		Formulas.formatNumber(snapshot.ratesPerHour.coins),
		snapshot.ratesPerHour.tickets,
		p.passes and p.passes.VIP and Camp.VIP_OFFLINE_CAP_HOURS or Camp.OFFLINE_CAP_HOURS,
		p.passes and p.passes.VIP and " (VIP)" or ""
	)
end

function Screen.build(host, ctx)
	Screen.ctx = ctx
	local C, Theme = ctx.C, ctx.Theme
	local root = C.panel({
		Name = "Camp",
		Size = UDim2.fromOffset(860, 460),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = host,
	}, "Camp")
	ui.cards = C.frame({
		Size = UDim2.new(1, -16, 0, 330),
		Position = UDim2.fromOffset(8, 40),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.list(ui.cards, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	ui.summary = C.label({
		Size = UDim2.new(1, -200, 0, 40),
		Position = UDim2.new(0, 8, 1, -76),
		TextSize = 9,
		TextColor3 = Theme.Colors.textDim,
		Parent = root,
	})
	C.button({
		Size = UDim2.fromOffset(180, 40),
		Position = UDim2.new(1, -190, 1, -76),
		Text = "COLLECT",
		BackgroundColor3 = Theme.Colors.good,
		TextSize = 12,
		Parent = root,
	}, function()
		local ok, err, got = ctx.Net.invoke("CampCollect")
		if ok then
			ctx.toast(
				string.format(
					"Collected %d coins, %d tickets, %d xp%s",
					got.coins,
					got.tickets,
					got.xp,
					got.levelUps > 0 and (", " .. got.levelUps .. " level-ups!") or ""
				),
				"good"
			)
		else
			ctx.toast(err, "bad")
		end
		fetch(ctx)
		refresh(ctx)
	end)
	C.label({
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.new(0, 8, 1, -30),
		Text = "Idle pets work while you are away (even offline). Pets in your team or on an expedition cannot work.",
		TextSize = 8,
		TextColor3 = Theme.Colors.textDim,
		Parent = root,
	})
	C.button({
		Size = UDim2.fromOffset(28, 24),
		Position = UDim2.new(1, -31, 0, 3),
		Text = "X",
		BackgroundColor3 = Theme.Colors.bad,
		Parent = root,
	}, function()
		ctx.Screens.close()
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			if root.Visible then
				fetch(ctx)
				refresh(ctx)
			end
		end
	end)
	ctx.State.onKeys({ "coins", "camp", "pets" }, function()
		if root.Visible then
			refresh(ctx)
		end
	end)
	return root
end

function Screen.onOpen()
	fetch(Screen.ctx)
	refresh(Screen.ctx)
end

return Screen
