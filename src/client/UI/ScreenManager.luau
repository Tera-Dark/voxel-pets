--!nonstrict
-- One main screen at a time. Screens are modules: { build(host, ctx) -> frame, onOpen?(frame, arg), onClose?(frame) }
-- Failure isolation: a screen whose build() throws is replaced by an error panel (and logged to
-- the dev log); a throwing onOpen/onClose shows a toast. Other screens keep working.
local UserInputService = game:GetService("UserInputService")

local ScreenManager = {}
local screens = {} -- name -> { module, frame, failed }
local current = nil
local host = nil
local ctx = nil

local opened = Instance.new("BindableEvent")
ScreenManager.Opened = opened.Event -- (name)

local function traceback(err)
	return tostring(err) .. "\n" .. debug.traceback(nil, 2)
end

local function errorPanel(name: string, err)
	local C = ctx.C
	local frame = C.panel({
		Name = name .. "_Error",
		Size = UDim2.fromOffset(540, 240),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 20,
		Parent = host,
	}, name .. " could not open")
	C.label({
		Size = UDim2.new(1, -24, 1, -90),
		Position = UDim2.fromOffset(12, 40),
		Text = "This screen hit an error. Please take a screenshot and send it to the developer.\n\n"
			.. string.sub(tostring(err), 1, 400),
		TextSize = 10,
		ZIndex = 21,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = frame,
	})
	C.button({
		Size = UDim2.fromOffset(120, 30),
		Position = UDim2.new(0.5, -60, 1, -40),
		Text = "Close",
		ZIndex = 21,
		BackgroundColor3 = ctx.Theme.Colors.bad,
		Parent = frame,
	}, function()
		ScreenManager.close()
	end)
	return frame
end

local function call(name: string, what: string, fn, ...)
	local ok, err = xpcall(fn, traceback, ...)
	if not ok then
		warn("[Screens] " .. name .. "." .. what .. " failed: " .. tostring(err))
		if ctx and ctx.toast then
			ctx.toast("Something went wrong on the " .. name .. " screen", "bad")
		end
	end
	return ok
end

function ScreenManager.init(hostFrame, context)
	host = hostFrame
	ctx = context
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if ctx and ctx.C and ctx.C.closeTopModal and ctx.C.closeTopModal() then
				return -- a window was open: close only that
			end
			ScreenManager.close()
		end
	end)
end

-- Scales a screen panel down (never up) so it fits the logical canvas with a margin.
local function fit(frame)
	if not (ctx and ctx.canvasSize) or not frame:IsA("GuiObject") then
		return
	end
	local w, h = frame.Size.X.Offset, frame.Size.Y.Offset
	if frame.Size.X.Scale > 0 or frame.Size.Y.Scale > 0 or w <= 0 or h <= 0 then
		return -- full-screen / scale-sized screens already fit
	end
	local canvas = ctx.canvasSize()
	local s = math.min(1, (canvas.X - 24) / w, (canvas.Y - 24) / h)
	local scaler = frame:FindFirstChild("FitScale")
	if not scaler then
		scaler = Instance.new("UIScale")
		scaler.Name = "FitScale"
		scaler.Parent = frame
	end
	scaler.Scale = math.max(0.5, s)
end

function ScreenManager.refit()
	for _, entry in screens do
		if entry.frame then
			pcall(fit, entry.frame)
		end
	end
end

function ScreenManager.register(name: string, module)
	screens[name] = { module = module, frame = nil, failed = false }
end

function ScreenManager.open(name: string, arg)
	local entry = screens[name]
	if not entry then
		warn("[Screens] unknown screen " .. tostring(name))
		return
	end
	if current and current ~= name then
		ScreenManager.close()
	end
	if not entry.frame then
		local ok, frame = xpcall(entry.module.build, traceback, host, ctx)
		if ok and typeof(frame) == "Instance" then
			entry.frame = frame
		else
			warn("[Screens] " .. name .. ".build failed: " .. tostring(frame))
			entry.failed = true
			entry.frame = errorPanel(name, if ok then "build() returned no frame" else frame)
		end
		entry.frame.Visible = false
	end
	pcall(fit, entry.frame)
	entry.frame.Visible = true
	current = name
	if entry.module.onOpen and not entry.failed then
		call(name, "onOpen", entry.module.onOpen, entry.frame, arg)
	end
	opened:Fire(name)
end

function ScreenManager.close()
	if not current then
		return
	end
	local name = current
	local entry = screens[name]
	current = nil
	if entry and entry.frame then
		entry.frame.Visible = false
		if entry.module.onClose and not entry.failed then
			call(name, "onClose", entry.module.onClose, entry.frame)
		end
	end
	opened:Fire(nil)
end

function ScreenManager.toggle(name: string, arg)
	if current == name then
		ScreenManager.close()
	else
		ScreenManager.open(name, arg)
	end
end

function ScreenManager.current()
	return current
end

function ScreenManager.refresh(name: string?)
	local key = name or current or ""
	local entry = screens[key]
	if
		entry
		and entry.frame
		and entry.frame.Visible
		and entry.module.onOpen
		and not entry.failed
	then
		call(key, "refresh", entry.module.onOpen, entry.frame)
	end
end

return ScreenManager
