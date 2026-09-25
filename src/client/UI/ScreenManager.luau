--!nonstrict
-- One main screen at a time. Screens are modules: { build(host, ctx) -> frame, onOpen?(frame, arg), onClose?(frame) }
local UserInputService = game:GetService("UserInputService")

local ScreenManager = {}
local screens = {} -- name -> { module, frame }
local current = nil
local host = nil
local ctx = nil

local opened = Instance.new("BindableEvent")
ScreenManager.Opened = opened.Event -- (name)

function ScreenManager.init(hostFrame, context)
	host = hostFrame
	ctx = context
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			ScreenManager.close()
		end
	end)
end

function ScreenManager.register(name: string, module)
	screens[name] = { module = module, frame = nil }
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
		entry.frame = entry.module.build(host, ctx)
		entry.frame.Visible = false
	end
	entry.frame.Visible = true
	current = name
	if entry.module.onOpen then
		entry.module.onOpen(entry.frame, arg)
	end
	opened:Fire(name)
end

function ScreenManager.close()
	if not current then
		return
	end
	local entry = screens[current]
	if entry.frame then
		entry.frame.Visible = false
		if entry.module.onClose then
			entry.module.onClose(entry.frame)
		end
	end
	current = nil
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
	local entry = screens[name or current or ""]
	if entry and entry.frame and entry.frame.Visible and entry.module.onOpen then
		entry.module.onOpen(entry.frame)
	end
end

return ScreenManager
