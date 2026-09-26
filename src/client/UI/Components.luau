--!nonstrict
-- Small UI kit in the pixel theme. Everything is built from plain Instances (no external assets).
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.PixelTheme)

local C = {}
local Colors = Theme.Colors

-- Property assignment never throws: a bad key is reported once (dev log) and skipped, so one
-- typo cannot take a whole screen down. Parent is assigned last. Keys are also validated
-- statically against the Roblox API dump (scripts/check_roblox_api.py, run in CI).
local warned = {}
local function apply(inst, props)
	local parent = nil
	for k, v in props or {} do
		if k == "Parent" then
			parent = v
		else
			local ok, err = pcall(function()
				inst[k] = v
			end)
			if not ok then
				local id = inst.ClassName .. "." .. tostring(k)
				if not warned[id] then
					warned[id] = true
					warn("[UI] cannot set " .. id .. ": " .. tostring(err))
				end
			end
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
C.apply = apply

-- Generic constructor: C.new("Frame", { Size = ..., Parent = ... }, { child1, child2 })
function C.new(className: string, props, children)
	local inst = Instance.new(className)
	local parent = props and props.Parent
	for k, v in props or {} do
		if k ~= "Parent" then
			apply(inst, { [k] = v })
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function C.stroke(parent, color, thickness)
	return C.new("UIStroke", {
		Color = color or Colors.border,
		Thickness = thickness or Theme.Border,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function C.padding(parent, px)
	px = px or Theme.Pad
	return C.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function C.list(parent, padding, direction, hAlign)
	return C.new("UIListLayout", {
		Padding = UDim.new(0, padding or 6),
		FillDirection = direction or Enum.FillDirection.Vertical,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function C.grid(parent, cellW, cellH, pad)
	return C.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cellW, cellH),
		CellPadding = UDim2.fromOffset(pad or 6, pad or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function C.frame(props)
	local f = C.new("Frame", {
		BackgroundColor3 = Colors.panel,
		BorderSizePixel = 0,
	})
	apply(f, props)
	return f
end

-- Panel with the chunky pixel border + optional title bar.
function C.panel(props, title)
	local f = C.frame(props)
	C.stroke(f)
	if title then
		C.new("TextLabel", {
			Name = "Title",
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Colors.panelLight,
			BorderSizePixel = 0,
			Text = title,
			TextColor3 = Colors.accent,
			FontFace = Theme.font(),
			TextSize = 14,
			Parent = f,
		})
	end
	return f
end

function C.label(props)
	local l = C.new("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = Colors.text,
		FontFace = Theme.font(),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Text = "",
	})
	apply(l, props)
	return l
end

function C.button(props, onClick)
	local b = C.new("TextButton", {
		BackgroundColor3 = Colors.info,
		BorderSizePixel = 0,
		TextColor3 = Colors.text,
		FontFace = Theme.font(),
		TextSize = 12,
		AutoButtonColor = false,
		Text = "Button",
	})
	apply(b, props)
	C.stroke(b)
	local base = b.BackgroundColor3
	b.MouseEnter:Connect(function()
		if b.Active then
			b.BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.15)
		end
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = base
	end)
	if onClick then
		b.Activated:Connect(function()
			if b.Active then
				onClick()
			end
		end)
	end
	-- allow later recolor
	b:GetAttributeChangedSignal("BaseColor"):Connect(function()
		base = b:GetAttribute("BaseColor")
		b.BackgroundColor3 = base
	end)
	return b
end

function C.setEnabled(button, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = false
	button.TextColor3 = enabled and Colors.text or Colors.textDim
	button.BackgroundTransparency = enabled and 0 or 0.5
end

-- Progress bar: returns frame + set(fraction, text?)
function C.bar(props, color, backColor)
	local outer = C.frame({ BackgroundColor3 = backColor or Colors.hpBack })
	apply(outer, props)
	C.stroke(outer, Colors.border, 2)
	local fill = C.frame({
		BackgroundColor3 = color or Colors.hp,
		Size = UDim2.fromScale(1, 1),
		Parent = outer,
	})
	local text = C.label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 10,
		TextStrokeTransparency = 0,
		Parent = outer,
	})
	local api = { frame = outer, fill = fill, text = text }
	function api.set(fraction: number, label: string?, animate: boolean?)
		fraction = math.clamp(fraction, 0, 1)
		if animate then
			TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(fraction, 1) })
				:Play()
		else
			fill.Size = UDim2.fromScale(fraction, 1)
		end
		text.Text = label or ""
	end
	return api
end

function C.scroll(props)
	local s = C.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Colors.borderLight,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	apply(s, props)
	return s
end

-- Open modals, newest last (Esc closes the top-most one first: C.closeTopModal()).
local modalStack = {}

function C.closeTopModal(): boolean
	for i = #modalStack, 1, -1 do
		local overlay = modalStack[i]
		table.remove(modalStack, i)
		if overlay.Parent then
			overlay:Destroy()
			return true
		end
	end
	return false
end

-- Full-screen modal window; returns the content frame and a close() function.
function C.modal(parent, title, size)
	local overlay = C.frame({
		Name = "Modal_" .. title,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		ZIndex = 50,
		Parent = parent,
	})
	local window = C.panel({
		Size = size or UDim2.fromOffset(520, 380),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 51,
		Parent = overlay,
	}, title)
	window.Title.ZIndex = 52
	local content = C.frame({
		Size = UDim2.new(1, 0, 1, -30),
		Position = UDim2.fromOffset(0, 30),
		BackgroundTransparency = 1,
		ZIndex = 52,
		Parent = window,
	})
	C.padding(content)
	local closeBtn = C.button({
		Size = UDim2.fromOffset(28, 24),
		Position = UDim2.new(1, -31, 0, 3),
		Text = "X",
		BackgroundColor3 = Colors.bad,
		ZIndex = 53,
		Parent = window,
	}, function()
		overlay:Destroy()
	end)
	closeBtn.ZIndex = 53
	table.insert(modalStack, overlay)
	return content, function()
		if overlay.Parent then
			overlay:Destroy()
		end
	end, overlay
end

-- Toast notifications (bottom center)
local toastHost = nil
function C.toast(parent, text, kind)
	if not toastHost or not toastHost.Parent then
		toastHost = C.frame({
			Name = "Toasts",
			Size = UDim2.fromOffset(420, 200),
			Position = UDim2.new(0.5, 0, 1, -150), -- above the dock / action bar
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			ZIndex = 90,
			Parent = parent,
		})
		C.list(toastHost, 4, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)
		toastHost.UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	end
	local color = kind == "bad" and Colors.bad
		or (kind == "good" and Colors.good or Colors.panelLight)
	local t = C.frame({
		Size = UDim2.new(1, 0, 0, 30),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = color,
		ZIndex = 91,
		Parent = toastHost,
	})
	C.stroke(t)
	C.padding(t, 6)
	C.label({
		Size = UDim2.new(1, 0, 0, 18),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 92,
		Parent = t,
	})
	task.delay(3, function()
		if t.Parent then
			TweenService:Create(t, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			task.wait(0.3)
			t:Destroy()
		end
	end)
end

-- Simple confirm dialog
function C.confirm(parent, title, text, onYes)
	local content, close = C.modal(parent, title, UDim2.fromOffset(420, 200))
	C.label({ Size = UDim2.new(1, 0, 0, 80), Text = text, ZIndex = 53, Parent = content })
	local row = C.frame({
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.new(0, 0, 1, -40),
		BackgroundTransparency = 1,
		ZIndex = 53,
		Parent = content,
	})
	C.list(row, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	local yes = C.button({
		Size = UDim2.fromOffset(140, 36),
		Text = "Confirm",
		BackgroundColor3 = Colors.good,
		ZIndex = 54,
		Parent = row,
	}, function()
		close()
		onYes()
	end)
	yes.ZIndex = 54
	local no = C.button({
		Size = UDim2.fromOffset(140, 36),
		Text = "Cancel",
		BackgroundColor3 = Colors.bad,
		ZIndex = 54,
		Parent = row,
	}, close)
	no.ZIndex = 54
end

-- Compact currency pill "icon value"
function C.currency(parent, currency, value, order)
	local f = C.frame({
		Size = UDim2.fromOffset(120, 26),
		BackgroundColor3 = Colors.panel,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	C.stroke(f, Colors.border, 2)
	local dot = C.frame({
		Size = UDim2.fromOffset(12, 12),
		Position = UDim2.fromOffset(7, 7),
		BackgroundColor3 = Theme.currencyColor(currency),
		Parent = f,
	})
	C.stroke(dot, Colors.border, 1)
	local l = C.label({
		Size = UDim2.new(1, -26, 1, 0),
		Position = UDim2.fromOffset(24, 0),
		Text = tostring(value),
		TextSize = 11,
		Parent = f,
	})
	return f, l
end

return C
