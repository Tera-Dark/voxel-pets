--!nonstrict
-- Roguelike expedition: start panel + talents, branching map, relic/event/shop/campfire choices, summary.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Relics = require(Shared.Config.Relics)
local Talents = require(Shared.Config.Talents)
local Events = require(Shared.Expedition.Events)
local MapGen = require(Shared.Expedition.MapGen)
local Run = require(Shared.Expedition.Run)

local Screen = {}
local ui = {}
local view = nil
local KIND_SHORT = {
	Battle = "FIGHT",
	Elite = "ELITE",
	Event = "?",
	Shop = "SHOP",
	Campfire = "REST",
	Treasure = "LOOT",
	Boss = "BOSS",
}

local function fetch(ctx)
	local ok, err, v = ctx.Net.invoke("GetExpedition")
	if ok then
		view = v
	else
		ctx.toast(err, "bad")
	end
end

local function clear(frame)
	for _, child in frame:GetChildren() do
		if
			not child:IsA("UIListLayout")
			and not child:IsA("UIPadding")
			and not child:IsA("UIGridLayout")
		then
			child:Destroy()
		end
	end
end

local function relicCard(ctx, parent, relicId, buttonText, onPick, price)
	local C, Theme = ctx.C, ctx.Theme
	local def = Relics[relicId]
	local card = C.panel({ Size = UDim2.fromOffset(190, 150), Parent = parent })
	C.label({
		Size = UDim2.new(1, -12, 0, 30),
		Position = UDim2.fromOffset(6, 4),
		Text = def.displayName,
		TextSize = 10,
		TextColor3 = Theme.Rarity[def.rarity],
		Parent = card,
	})
	C.label({
		Size = UDim2.new(1, -12, 0, 14),
		Position = UDim2.fromOffset(6, 32),
		Text = def.rarity,
		TextSize = 8,
		TextColor3 = Theme.Colors.textDim,
		Parent = card,
	})
	C.label({
		Size = UDim2.new(1, -12, 0, 64),
		Position = UDim2.fromOffset(6, 48),
		Text = def.description,
		TextSize = 8,
		Parent = card,
	})
	local b = C.button({
		Size = UDim2.new(1, -12, 0, 26),
		Position = UDim2.new(0, 6, 1, -32),
		Text = buttonText .. (price and (" " .. price .. "g") or ""),
		TextSize = 9,
		BackgroundColor3 = Theme.Colors.good,
		Parent = card,
	}, onPick)
	return card, b
end

local function act(ctx, remote, ...)
	local ok, err, v = ctx.Net.invoke(remote, ...)
	if ok then
		view = v
		Screen.refresh(ctx)
	else
		ctx.toast(err, "bad")
	end
	return ok
end

local function renderPending(ctx, run)
	local C, Theme = ctx.C, ctx.Theme
	local p = run.pending
	local box = ui.pending
	clear(box)
	box.Visible = true
	if p.type == "Relic" then
		C.label({
			Size = UDim2.new(1, 0, 0, 20),
			Text = string.format(
				"%s: choose a relic%s",
				p.source,
				p.remaining > 1 and (" (" .. p.remaining .. " picks)") or ""
			),
			TextSize = 11,
			TextColor3 = Theme.Colors.accent,
			Parent = box,
		})
		local row = C.frame({
			Size = UDim2.new(1, 0, 0, 150),
			Position = UDim2.fromOffset(0, 26),
			BackgroundTransparency = 1,
			Parent = box,
		})
		C.list(row, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
		for i, id in p.offers do
			relicCard(ctx, row, id, "Take", function()
				act(ctx, "ExpeditionChoose", i)
			end)
		end
		local bottom = C.frame({
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromOffset(0, 184),
			BackgroundTransparency = 1,
			Parent = box,
		})
		C.list(bottom, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
		C.button({
			Size = UDim2.fromOffset(160, 28),
			Text = "Skip (+" .. Run.GOLD.Skip .. " gold)",
			TextSize = 9,
			BackgroundColor3 = Theme.Colors.panelLight,
			Parent = bottom,
		}, function()
			act(ctx, "ExpeditionChoose", 0)
		end)
		local reroll = C.button({
			Size = UDim2.fromOffset(160, 28),
			Text = "Reroll (" .. run.rerollsLeft .. " left)",
			TextSize = 9,
			BackgroundColor3 = Theme.Colors.info,
			Parent = bottom,
		}, function()
			act(ctx, "ExpeditionChoose", -1)
		end)
		C.setEnabled(reroll, run.rerollsLeft > 0)
	elseif p.type == "Event" then
		local ev = Events.ById[p.eventId]
		C.label({
			Size = UDim2.new(1, 0, 0, 20),
			Text = ev.title,
			TextSize = 12,
			TextColor3 = Theme.Colors.accent,
			Parent = box,
		})
		C.label({
			Size = UDim2.new(1, 0, 0, 50),
			Position = UDim2.fromOffset(0, 24),
			Text = ev.text,
			TextSize = 9,
			Parent = box,
		})
		for i, choice in ev.choices do
			C.button({
				Size = UDim2.new(1, 0, 0, 30),
				Position = UDim2.fromOffset(0, 80 + (i - 1) * 36),
				Text = choice.text,
				TextSize = 9,
				BackgroundColor3 = i == 1 and Theme.Colors.info or Theme.Colors.panelLight,
				Parent = box,
			}, function()
				act(ctx, "ExpeditionChoose", i)
			end)
		end
	elseif p.type == "Shop" then
		C.label({
			Size = UDim2.new(1, 0, 0, 20),
			Text = "Shop  -  gold: " .. run.gold,
			TextSize = 11,
			TextColor3 = Theme.Colors.accent,
			Parent = box,
		})
		local row = C.frame({
			Size = UDim2.new(1, 0, 0, 150),
			Position = UDim2.fromOffset(0, 26),
			BackgroundTransparency = 1,
			Parent = box,
		})
		C.list(row, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
		for i, item in p.items do
			local _, b = relicCard(ctx, row, item.relicId, "Buy", function()
				act(ctx, "ExpeditionChoose", i)
			end, item.price)
			C.setEnabled(b, run.gold >= item.price)
		end
		local bottom = C.frame({
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromOffset(0, 184),
			BackgroundTransparency = 1,
			Parent = box,
		})
		C.list(bottom, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
		local healBtn = C.button({
			Size = UDim2.fromOffset(200, 28),
			Text = string.format("Heal 30%% (%dg)", p.healPrice),
			TextSize = 9,
			BackgroundColor3 = Theme.Colors.good,
			Parent = bottom,
		}, function()
			act(ctx, "ExpeditionChoose", #p.items + 1)
		end)
		C.setEnabled(healBtn, not p.healed and run.gold >= p.healPrice)
		C.button({
			Size = UDim2.fromOffset(120, 28),
			Text = "Leave",
			TextSize = 9,
			BackgroundColor3 = Theme.Colors.panelLight,
			Parent = bottom,
		}, function()
			act(ctx, "ExpeditionChoose", 0)
		end)
	elseif p.type == "Campfire" then
		C.label({
			Size = UDim2.new(1, 0, 0, 20),
			Text = "Campfire",
			TextSize = 12,
			TextColor3 = Theme.Colors.accent,
			Parent = box,
		})
		C.button({
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromOffset(0, 30),
			Text = string.format(
				"Rest: heal %d%%",
				math.floor((Run.CAMPFIRE_HEAL + run.effects.campfireBonus) * 100 + 0.5)
			),
			TextSize = 9,
			BackgroundColor3 = Theme.Colors.good,
			Parent = box,
		}, function()
			act(ctx, "ExpeditionChoose", 1)
		end)
		C.button({
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromOffset(0, 66),
			Text = "Train: +5% ATK for the rest of the run",
			TextSize = 9,
			BackgroundColor3 = Theme.Colors.info,
			Parent = box,
		}, function()
			act(ctx, "ExpeditionChoose", 2)
		end)
	end
end

local function renderMap(ctx, run)
	local C, Theme = ctx.C, ctx.Theme
	clear(ui.map)
	local available = view.available or {}
	local cellW, cellH = 66, 44
	for col = 1, MapGen.COLUMNS do
		for _, node in run.map.columns[col] do
			local visited = run.visited[tostring(node.id)] == true
			local isCurrent = run.currentNodeId == node.id
			local canGo = table.find(available, node.id) ~= nil
			local color = Theme.Colors.panel
			if isCurrent then
				color = Theme.Colors.accent
			elseif canGo then
				color = Theme.Colors.good
			elseif visited then
				color = Theme.Colors.panelLight
			elseif node.kind == "Boss" then
				color = Theme.Colors.bad
			elseif node.kind == "Elite" then
				color = Theme.Colors.essence
			end
			local text = KIND_SHORT[node.kind]
			if node.enemy then
				text = text .. "\n" .. Pets[node.enemy].displayName
			end
			local b = C.button({
				Size = UDim2.fromOffset(cellW, cellH),
				Position = UDim2.fromOffset((col - 1) * (cellW + 6), (node.lane - 1) * (cellH + 8)),
				Text = text,
				TextSize = 7,
				BackgroundColor3 = color,
				Parent = ui.map,
			}, function()
				if canGo then
					act(ctx, "ExpeditionMove", node.id)
				end
			end)
			C.setEnabled(b, canGo or isCurrent)
			if visited and not isCurrent then
				b.BackgroundTransparency = 0.6
			end
		end
	end
	-- edges as thin frames (straight connections only look right on same/adjacent lanes; good enough)
	for _, node in run.map.nodes do
		for _, nextId in node.next do
			local nxt = run.map.nodes[nextId]
			local x1 = (node.col - 1) * (cellW + 6) + cellW
			local y1 = (node.lane - 1) * (cellH + 8) + cellH / 2
			local y2 = (nxt.lane - 1) * (cellH + 8) + cellH / 2
			local line = C.frame({
				Size = UDim2.fromOffset(6, math.max(2, math.abs(y2 - y1) + 2)),
				Position = UDim2.fromOffset(x1, math.min(y1, y2)),
				BackgroundColor3 = Theme.Colors.borderLight,
				ZIndex = 0,
				Parent = ui.map,
			})
			line.BackgroundTransparency = 0.5
		end
	end
end

local function renderStatus(ctx, run)
	local lines = {
		string.format(
			"Floor %d / %d   HP %d%%   Gold %d",
			run.floor,
			Run.MAX_FLOORS,
			math.floor(run.hpFraction * 100 + 0.5),
			run.gold
		),
		string.format(
			"Marks earned %d   Nodes %d   Rerolls %d",
			run.marks,
			run.nodesCleared,
			run.rerollsLeft
		),
		"Relics (" .. #run.relics .. "):",
	}
	for _, id in run.relics do
		table.insert(lines, "  - " .. Relics[id].displayName)
	end
	table.insert(lines, "")
	for i = math.max(1, #run.log - 5), #run.log do
		table.insert(lines, "> " .. run.log[i])
	end
	ui.status.Text = table.concat(lines, "\n")
	local _ = ctx
end

local function renderTalents(ctx)
	local C, Theme = ctx.C, ctx.Theme
	clear(ui.talents)
	local owned = view.talents or {}
	local marks = view.marks or 0
	for i, node in Talents.Nodes do
		local has = owned[node.id]
		local can = Talents.canBuy(node.id, owned, marks)
		local b = C.button({
			Size = UDim2.fromOffset(160, 44),
			Text = string.format(
				"%s\n%s",
				node.displayName,
				has and "OWNED" or (node.cost .. " marks")
			),
			TextSize = 8,
			LayoutOrder = i,
			BackgroundColor3 = has and Theme.Colors.good
				or (can and Theme.Colors.info or Theme.Colors.panel),
			Parent = ui.talents,
		}, function()
			if can then
				if act(ctx, "ExpeditionBuyTalent", node.id) then
					ctx.toast("Talent learned: " .. node.displayName, "good")
				end
			else
				ctx.toast(node.description, "info")
			end
		end)
		C.setEnabled(b, true)
	end
end

local function renderStart(ctx)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State
	clear(ui.start)
	ui.start.Visible = true
	local p = State.profile
	local lines = {
		"Pick one pet and descend " .. Run.MAX_FLOORS .. " floors of branching nodes.",
		"Battles are automatic; you choose the path, relics and events.",
		"HP carries over between fights. Fall and the run ends - you keep the Marks.",
		"",
		string.format(
			"Tickets: %d   Marks: %d   Best floor: %d   Runs: %d",
			p.tickets or 0,
			p.marks or 0,
			p.expedition.bestFloor or 0,
			p.expedition.runs or 0
		),
	}
	if p.expedition.lastSummary then
		local s = p.expedition.lastSummary
		table.insert(
			lines,
			string.format(
				"Last run: %s - floors %d, %d battles, +%d marks, +%d coins%s",
				s.status,
				s.floorsCleared,
				s.battlesWon,
				s.marks,
				s.coins,
				s.exclusiveDrop and ("  FOUND " .. s.exclusiveDrop .. "!") or ""
			)
		)
	end
	C.label({
		Size = UDim2.new(1, 0, 0, 110),
		Text = table.concat(lines, "\n"),
		TextSize = 9,
		Parent = ui.start,
	})
	local startBtn = C.button({
		Size = UDim2.fromOffset(260, 40),
		Position = UDim2.fromOffset(0, 120),
		Text = "START EXPEDITION (1 ticket)",
		TextSize = 11,
		BackgroundColor3 = Theme.Colors.bad,
		Parent = ui.start,
	}, function()
		ctx.openPetPicker("Choose your expedition pet", function(uid)
			local busy = State.isBusy(uid)
			return busy == nil or busy == "Active"
		end, function(uid)
			act(ctx, "ExpeditionStart", uid)
		end)
	end)
	if not view.unlocked then
		C.setEnabled(startBtn, false)
		startBtn.Text = "Clear stage 1-5 to unlock"
	elseif (p.tickets or 0) < 1 then
		C.setEnabled(startBtn, false)
		startBtn.Text = "No tickets (Outpost / shop)"
	end
end

function Screen.refresh(ctx)
	if not view then
		return
	end
	local run = view.run
	ui.start.Visible = false
	ui.map.Visible = false
	ui.pending.Visible = false
	ui.status.Visible = false
	ui.abandon.Visible = false
	if run then
		ui.map.Visible = true
		ui.status.Visible = true
		ui.abandon.Visible = true
		renderMap(ctx, run)
		renderStatus(ctx, run)
		if run.pending then
			renderPending(ctx, run)
		end
	else
		renderStart(ctx)
	end
	renderTalents(ctx)
end

function Screen.build(host, ctx)
	Screen.ctx = ctx
	local C, Theme = ctx.C, ctx.Theme
	local root = C.panel({
		Name = "Expedition",
		Size = UDim2.fromOffset(920, 540),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = host,
	}, "Expedition")
	ui.start = C.frame({
		Size = UDim2.fromOffset(560, 200),
		Position = UDim2.fromOffset(12, 40),
		BackgroundTransparency = 1,
		Parent = root,
	})
	ui.map = C.frame({
		Size = UDim2.fromOffset(720, 160),
		Position = UDim2.fromOffset(12, 40),
		BackgroundTransparency = 1,
		Parent = root,
	})
	ui.pending = C.panel({
		Size = UDim2.fromOffset(640, 230),
		Position = UDim2.fromOffset(12, 210),
		Parent = root,
	})
	C.padding(ui.pending, 8)
	ui.status = C.label({
		Size = UDim2.fromOffset(240, 400),
		Position = UDim2.fromOffset(664, 210),
		TextSize = 8,
		Parent = root,
	})
	ui.abandon = C.button({
		Size = UDim2.fromOffset(120, 26),
		Position = UDim2.new(1, -160, 0, 6),
		Text = "Abandon",
		TextSize = 9,
		BackgroundColor3 = Theme.Colors.bad,
		Parent = root,
	}, function()
		C.confirm(
			ctx.gui,
			"Abandon run",
			"Abandon the expedition? You keep half the Marks earned so far.",
			function()
				act(ctx, "ExpeditionAbandon")
			end
		)
	end)
	local talentsPanel = C.panel(
		{ Size = UDim2.fromOffset(560, 250), Position = UDim2.fromOffset(12, 250), Parent = root },
		"Talents (permanent, cost Marks)"
	)
	ui.talents = C.frame({
		Size = UDim2.new(1, -8, 1, -34),
		Position = UDim2.fromOffset(4, 32),
		BackgroundTransparency = 1,
		Parent = talentsPanel,
	})
	C.grid(ui.talents, 160, 44, 6)
	ui.talentsPanel = talentsPanel
	C.button({
		Size = UDim2.fromOffset(28, 24),
		Position = UDim2.new(1, -31, 0, 3),
		Text = "X",
		BackgroundColor3 = Theme.Colors.bad,
		Parent = root,
	}, function()
		ctx.Screens.close()
	end)
	ctx.State.onKeys({ "expedition", "tickets", "marks" }, function()
		if root.Visible then
			fetch(ctx)
			Screen.refresh(ctx)
			talentsPanel.Visible = view and view.run == nil
		end
	end)
	return root
end

function Screen.onOpen()
	fetch(Screen.ctx)
	Screen.refresh(Screen.ctx)
	ui.talentsPanel.Visible = view and view.run == nil
end

return Screen
