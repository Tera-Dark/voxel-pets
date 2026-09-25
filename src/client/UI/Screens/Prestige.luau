--!nonstrict
-- Soft prestige: preview points, what resets / what stays, confirm.
local Screen = {}
local ui = {}

local function render(ctx)
	local C, Theme = ctx.C, ctx.Theme
	local ok, err, v = ctx.Net.invoke("GetPrestige")
	if not ok then
		ctx.toast(err, "bad")
		return
	end
	local lines = {
		string.format("Prestige count: %d     Points: %d", v.count, v.currentPoints),
		string.format(
			"Prestige now for +%d points  ->  camp production x%.2f, pet stats x%.2f",
			v.points,
			v.productionMult,
			v.petStatMult
		),
		"",
		"RESETS:  stage progress, coins, camp levels & workers, expedition run",
		"KEEPS:   pets, gems, essence, shards, marks, talents, codex, passes, arena rating",
		"",
		"MILESTONES:",
	}
	for _, m in v.milestones do
		local reached = v.count >= m.count
		table.insert(
			lines,
			string.format("  %s  x%d  %s", reached and "[x]" or "[ ]", m.count, m.displayName)
		)
	end
	ui.text.Text = table.concat(lines, "\n")
	ui.button.Text = v.canPrestige and ("PRESTIGE  (+" .. v.points .. " points)")
		or "Defeat the zone 3 boss first"
	ui.button.BackgroundColor3 = v.canPrestige and Theme.Colors.bad or Theme.Colors.panel
	C.setEnabled(ui.button, v.canPrestige and v.points > 0)
	ui.points = v.points
end

function Screen.build(host, ctx)
	Screen.ctx = ctx
	local C, Theme = ctx.C, ctx.Theme
	local root = C.panel({
		Name = "Prestige",
		Size = UDim2.fromOffset(620, 380),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = host,
	}, "Prestige")
	ui.text = C.label({
		Size = UDim2.new(1, -24, 0, 260),
		Position = UDim2.fromOffset(12, 40),
		TextSize = 9,
		Parent = root,
	})
	ui.button = C.button({
		Size = UDim2.fromOffset(320, 36),
		Position = UDim2.new(0.5, -160, 1, -50),
		Text = "PRESTIGE",
		TextSize = 11,
		BackgroundColor3 = Theme.Colors.bad,
		Parent = root,
	}, function()
		C.confirm(
			ctx.gui,
			"Prestige",
			string.format(
				"Reset stages, coins and camp for +%d prestige points? Pets and gems are kept.",
				ui.points or 0
			),
			function()
				local ok, err, res = ctx.Net.invoke("Prestige")
				if ok then
					ctx.toast(
						string.format(
							"Prestige %d complete! +%d points (total %d)",
							res.count,
							res.points,
							res.total
						),
						"good"
					)
					ctx.Screens.close()
				else
					ctx.toast(err, "bad")
				end
			end
		)
	end)
	C.button({
		Size = UDim2.fromOffset(28, 24),
		Position = UDim2.new(1, -31, 0, 3),
		Text = "X",
		BackgroundColor3 = Theme.Colors.bad,
		Parent = root,
	}, function()
		ctx.Screens.close()
	end)
	return root
end

function Screen.onOpen()
	render(Screen.ctx)
end

return Screen
