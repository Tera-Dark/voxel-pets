--!nonstrict
-- Settings modal (opened from the gear button): battle speed, auto-skip, dock default.
local Settings = {}

function Settings.open(ctx)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State
	local content = C.modal(ctx.gui, "Settings", UDim2.fromOffset(380, 250))
	C.list(content, 8)
	local settings = State.profile.settings
	C.label({ Size = UDim2.new(1, 0, 0, 20), Text = "Battle speed", ZIndex = 53, Parent = content })
	local speeds = C.frame({
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		ZIndex = 53,
		Parent = content,
	})
	C.list(speeds, 6, Enum.FillDirection.Horizontal)
	local speedButtons = {}
	local function paint()
		for s, b in speedButtons do
			b:SetAttribute(
				"BaseColor",
				if s == settings.battleSpeed then Theme.Colors.good else Theme.Colors.panelLight
			)
		end
	end
	for _, s in { 1, 2, 3 } do
		speedButtons[s] = C.button(
			{ Size = UDim2.fromOffset(70, 32), Text = s .. "x", ZIndex = 54, Parent = speeds },
			function()
				settings.battleSpeed = s
				ctx.Net.invoke("SetSetting", "battleSpeed", s)
				paint()
			end
		)
	end
	paint()
	local skipBtn
	skipBtn = C.button({
		Size = UDim2.new(1, 0, 0, 32),
		Text = "Auto-skip battles: " .. (if settings.autoSkip then "ON" else "OFF"),
		ZIndex = 54,
		BackgroundColor3 = Theme.Colors.panelLight,
		Parent = content,
	}, function()
		settings.autoSkip = not settings.autoSkip
		ctx.Net.invoke("SetSetting", "autoSkip", settings.autoSkip)
		skipBtn.Text = "Auto-skip battles: " .. (if settings.autoSkip then "ON" else "OFF")
	end)
	C.label({
		Size = UDim2.new(1, 0, 0, 52),
		Text = "Combat is fully automatic: your choices are made before the fight - "
			.. "which pet, its level, and relics on expeditions. Esc closes windows.",
		TextSize = 9,
		TextColor3 = Theme.Colors.textDim,
		ZIndex = 53,
		Parent = content,
	})
end

return Settings
