--!nonstrict
-- Roguelike expedition screen: fetches run state from the server and orchestrates the panels
-- in ExpeditionView (start / map / choices / status / talents).
local View = require(script.Parent.Parent.ExpeditionView)

local Screen = {}
local ui = {}
local view = nil

local function fetch(ctx)
	local ok, err, v = ctx.Net.invoke("GetExpedition")
	if ok then
		view = v
	else
		ctx.toast(err, "bad")
	end
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
		View.renderMap(ctx, ui, view, act)
		View.renderStatus(ui, run)
		if run.pending then
			View.renderPending(ctx, ui, run, act)
		end
	else
		View.renderStart(ctx, ui, view, act)
	end
	View.renderTalents(ctx, ui, view, act)
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
		Name = "Start",
		Size = UDim2.fromOffset(560, 200),
		Position = UDim2.fromOffset(12, 40),
		BackgroundTransparency = 1,
		Parent = root,
	})
	ui.map = C.frame({
		Name = "Map",
		Size = UDim2.fromOffset(720, 160),
		Position = UDim2.fromOffset(12, 40),
		BackgroundTransparency = 1,
		Parent = root,
	})
	ui.pending = C.panel({
		Name = "Pending",
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
		Name = "Talents",
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
