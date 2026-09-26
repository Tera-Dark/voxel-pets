--!nonstrict
-- Client-side Roblox mock: runs the real client scripts (src/client) inside Lune, connected to the
-- real server services running under tools/roblox_mock (scheduler mode, shared virtual clock).
--
-- Fidelity where bugs actually hide:
--   * Instances are validated against the Roblox API dump (tools/data/roblox_api.json): unknown
--     members throw "X is not a valid member of Y", read-only writes throw, assignments are
--     type-checked (e.g. `label.Text = nil` or a Color3 into a UDim2 property throws).
--   * Remote payloads go through Roblox's serialization rules; mixed tables, sparse arrays,
--     non-string keys, functions and cycles are recorded in CM.remoteIssues.
--   * Errors in any client thread (event handlers, tasks) are recorded in CM.errors and fire
--     ScriptContext.Error like the engine does; warn() fires LogService.MessageOut.
-- Not simulated: rendering/layout, physics, input devices (tests "click" by firing Activated).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

local DT = require("./mock/datatypes")
local Instances = require("./mock/instances")
local typed, typeofX = DT.typed, DT.typeofX
local Vector3, Vector2, CFrame, Color3 = DT.Vector3, DT.Vector2, DT.CFrame, DT.Color3
local UDim, UDim2, TweenInfo = DT.UDim, DT.UDim2, DT.TweenInfo

local ClientMock = {}

function ClientMock.new(M, root, opts)
	opts = opts or {}
	assert(M.scheduler, "ClientMock needs the server mock in { scheduler = true } mode")
	local api = serde.decode("json", fs.readFile(root .. "/tools/data/roblox_api.json"))
	local classes = api.classes
	local Enum = DT.buildEnum(api)
	local I = Instances(api, M.scheduler, Enum)

	local CM = { errors = {}, warnings = {}, remoteIssues = {}, prints = {}, purchases = {} }
	local issueSeen = {}
	local function issue(msg)
		if not issueSeen[msg] then
			issueSeen[msg] = true
			table.insert(CM.remoteIssues, msg)
		end
	end

	local propInfo = I.propInfo
	local make, new, st, isInstance = I.make, I.new, I.st, I.isInstance
	local signalOf, checkValue, descendants, Impl = I.signalOf, I.checkValue, I.descendants, I.Impl
	CM.isInstance, CM.signal, CM.new = isInstance, signalOf, new

	-- ------------------------------------------------------------ remote serialization
	local function rcopy(v, where, seen)
		local t = type(v)
		if t == "table" then
			local mt = getmetatable(v)
			if type(mt) == "table" and rawget(mt, "__type") then
				return v
			end
			seen = seen or {}
			if seen[v] then
				issue(where .. ": cyclic table")
				return nil
			end
			seen[v] = true
			local n = #v
			local hasHash = false
			for k in v do
				local kt = type(k)
				if kt == "number" then
					if k < 1 or k > n or k % 1 ~= 0 then
						hasHash = true
						issue(
							where
								.. ": numeric key "
								.. tostring(k)
								.. " outside the array part (sparse)"
						)
					end
				elseif kt == "string" then
					hasHash = true
				else
					issue(where .. ": key of type " .. kt)
				end
			end
			if n > 0 and hasHash then
				issue(where .. ": mixed table (array + dictionary keys) loses data over remotes")
			end
			local out = {}
			for k, val in v do
				if type(val) == "function" then
					issue(where .. "." .. tostring(k) .. ": function value is dropped")
				else
					out[k] = rcopy(val, where .. "." .. tostring(k), seen)
				end
			end
			seen[v] = nil
			return out
		elseif t == "function" or t == "thread" then
			issue(where .. ": " .. t .. " cannot be sent")
			return nil
		end
		return v
	end
	local function rpack(where, ...)
		local args = table.pack(...)
		local out = { n = args.n }
		for i = 1, args.n do
			out[i] = rcopy(args[i], where .. "[" .. i .. "]")
		end
		return out
	end

	-- ------------------------------------------------------------ services
	local services = {}
	local playerObj -- client Player instance
	local serverPlayer

	local function service(name)
		local s = services[name]
		if s then
			return s
		end
		local c = classes[name]
		if not c or not table.find(c.tags, "Service") then
			error("'" .. tostring(name) .. "' is not a valid Service name", 2)
		end
		s = make(name)
		st(s).props.Name = name
		services[name] = s
		return s
	end

	Impl.RunService = {
		IsStudio = function()
			return opts.studio ~= false
		end,
		IsClient = function()
			return true
		end,
		IsServer = function()
			return false
		end,
		IsRunning = function()
			return true
		end,
	}
	Impl.Players = {
		GetPlayers = function()
			return { playerObj }
		end,
		GetPlayerByUserId = function(_, id)
			return if id == st(playerObj).props.UserId then playerObj else nil
		end,
	}
	Impl.StarterGui = {
		SetCoreGuiEnabled = function() end,
		GetCoreGuiEnabled = function()
			return true
		end,
		SetCore = function() end,
	}
	Impl.UserInputService = {
		GetLastInputType = function()
			return Enum.UserInputType.MouseButton1
		end,
		IsKeyDown = function()
			return false
		end,
		GetFocusedTextBox = function()
			return nil
		end,
	}
	Impl.MarketplaceService = {
		PromptGamePassPurchase = function(_, _, id)
			table.insert(CM.purchases, { kind = "pass", id = id })
		end,
		PromptProductPurchase = function(_, _, id)
			table.insert(CM.purchases, { kind = "product", id = id })
		end,
		UserOwnsGamePassAsync = function()
			return false
		end,
	}
	Impl.TweenService = {
		Create = function(_, inst, info, goals)
			if not isInstance(inst) then
				error(
					"TweenService:Create: argument 1 must be an Instance, got " .. typeofX(inst),
					2
				)
			end
			if typeofX(info) ~= "TweenInfo" then
				error("TweenService:Create: argument 2 must be a TweenInfo", 2)
			end
			for k, v in goals do
				local pi = propInfo(st(inst).class, k)
				if not pi then
					error(
						"TweenService:Create no property named '"
							.. k
							.. "' for object '"
							.. st(inst).props.Name
							.. "'",
						2
					)
				end
				checkValue(st(inst).class, k, pi.ptype, v)
			end
			local tween = make("Tween")
			st(tween).goals = { inst = inst, props = goals }
			return tween
		end,
	}
	Impl.Tween = {
		Play = function(tween)
			local g = st(tween).goals
			if not st(g.inst).destroyed then
				for k, v in g.props do
					g.inst[k] = v
				end
			end
			signalOf(tween, "Completed"):Fire(Enum.PlaybackState.Completed)
		end,
		Cancel = function() end,
		Pause = function() end,
	}
	Impl.Sound = {
		Play = function() end,
		Stop = function() end,
		Pause = function() end,
		Resume = function() end,
	}
	Impl.RemoteFunction = {
		InvokeServer = function(obj, ...)
			local name = st(obj).props.Name
			local rf = M.remotes.functions[name]
			while not (rf and rf.OnServerInvoke) do -- Roblox queues until a handler exists
				M.scheduler:wait(1)
				rf = M.remotes.functions[name]
			end
			local args = rpack("InvokeServer " .. name .. " args", ...)
			local res = table.pack(rf.OnServerInvoke(serverPlayer, table.unpack(args, 1, args.n)))
			local out = rpack(name .. " result", table.unpack(res, 1, res.n))
			return table.unpack(out, 1, out.n)
		end,
	}
	Impl.RemoteEvent = {
		FireServer = function() end,
	}
	Impl.Player = {
		Kick = function(_, reason)
			CM.kicked = reason
		end,
	}

	-- ------------------------------------------------------------ world + player
	local Workspace = service("Workspace")
	local camera = make("Camera")
	st(camera).props.Name = "Camera"
	camera.Parent = Workspace
	st(Workspace).props.CurrentCamera = camera

	serverPlayer = M.join(opts.userId or 3001, opts.name or "Tester")
	CM.serverPlayer = serverPlayer
	playerObj = make("Player")
	do
		local s = st(playerObj)
		s.props.Name = serverPlayer.Name
		s.props.DisplayName = serverPlayer.Name
		s.props.UserId = serverPlayer.UserId
		s.attrs = serverPlayer.attributes -- server-set attributes replicate to the client
	end
	local Players = service("Players")
	st(Players).props.LocalPlayer = playerObj
	playerObj.Parent = Players
	local playerGui = make("PlayerGui")
	st(playerGui).props.Name = "PlayerGui"
	playerGui.Parent = playerObj
	CM.player, CM.playerGui, CM.workspace = playerObj, playerGui, Workspace

	-- ReplicatedStorage: Shared (module tree) + Remotes (proxies of the server's remotes)
	local ReplicatedStorage = service("ReplicatedStorage")
	st(ReplicatedStorage).attrs = M.attributes

	-- ------------------------------------------------------------ module trees
	local SOURCES = {}
	-- Module tree nodes mirror Folder/ModuleScript instances: child indexing plus the lookup
	-- methods scripts use on them (FindFirstChild / WaitForChild).
	local nodeMethods = {}
	function nodeMethods.FindFirstChild(t, childName)
		return rawget(t, "__children")[childName]
	end
	function nodeMethods.WaitForChild(t, childName, timeout)
		local child = rawget(t, "__children")[childName]
		if not child and not timeout then
			error('Infinite yield on WaitForChild("' .. tostring(childName) .. '")', 2)
		end
		return child
	end
	local function node(name, path, parent)
		local n = { Name = name, __path = path, Parent = parent, __children = {} }
		return setmetatable(n, {
			__index = function(t, k)
				local child = rawget(t, "__children")[k]
				if child then
					return child
				end
				if nodeMethods[k] then
					return nodeMethods[k]
				end
				error(tostring(k) .. " is not a valid member of " .. name, 2)
			end,
		})
	end
	local function buildTree(dir, name, parent)
		local n = node(name, nil, parent)
		for _, entry in fs.readDir(dir) do
			local full = dir .. "/" .. entry
			if fs.isDir(full) then
				n.__children[entry] = buildTree(full, entry, n)
			elseif string.match(entry, "%.luau$") then
				local modName = string.gsub(
					string.gsub(string.gsub(entry, "%.server%.luau$", ""), "%.client%.luau$", ""),
					"%.luau$",
					""
				)
				n.__children[modName] = node(modName, full, n)
				SOURCES[full] = fs.readFile(full)
			end
		end
		return n
	end
	local sharedTree = buildTree(root .. "/src/shared", "Shared", nil)
	local clientTree = buildTree(root .. "/src/client", "Client", nil)
	st(ReplicatedStorage).extra = { Shared = sharedTree }

	local remotesFolder = make("Folder")
	st(remotesFolder).props.Name = "Remotes"
	for name in M.remotes.functions do
		local r = make("RemoteFunction")
		st(r).props.Name = name
		r.Parent = remotesFolder
	end
	for name in M.remotes.events do
		local r = make("RemoteEvent")
		st(r).props.Name = name
		r.Parent = remotesFolder
	end
	remotesFolder.Parent = ReplicatedStorage

	M.onFire = function(name, player, args)
		if player ~= nil and player ~= serverPlayer then
			return
		end
		local re = remotesFolder:FindFirstChild(name)
		if not re then
			return
		end
		local copy = rpack("event " .. name, table.unpack(args, 1, args.n))
		signalOf(re, "OnClientEvent"):Fire(table.unpack(copy, 1, copy.n))
	end

	-- ------------------------------------------------------------ env / loader
	local ScriptContext = service("ScriptContext")
	local LogService = service("LogService")
	M.onTaskError = function(err, co)
		local text = tostring(err)
		table.insert(CM.errors, text)
		signalOf(ScriptContext, "Error"):Fire(text, debug.traceback(co), nil)
	end

	local game = {
		PlaceId = M.services and 0 or 0,
		CreatorId = 1,
		JobId = "client",
		Workspace = Workspace,
	}
	game.CreatorType = Enum.CreatorType.User
	function game:GetService(name)
		return service(name)
	end

	local cache = {}
	local loadModule
	local function makeEnv(scriptNode)
		return {
			game = game,
			workspace = Workspace,
			script = scriptNode,
			Enum = Enum,
			Instance = { new = new },
			Vector3 = Vector3,
			Vector2 = Vector2,
			CFrame = CFrame,
			Color3 = Color3,
			UDim = UDim,
			UDim2 = UDim2,
			TweenInfo = TweenInfo,
			Font = {
				new = function(family, weight, style)
					return setmetatable(
						{ Family = family, Weight = weight, Style = style },
						typed("Font")
					)
				end,
				fromEnum = function(item)
					if typeofX(item) ~= "EnumItem" or item.EnumType.Name ~= "Font" then
						error("Font.fromEnum expects an Enum.Font item", 2)
					end
					return setmetatable({ Family = item.Name }, typed("Font"))
				end,
			},
			Random = {
				new = function()
					local r = {}
					function r.NextInteger(_, lo, hi)
						return math.random(lo, hi)
					end
					function r.NextNumber(_, lo, hi)
						lo, hi = lo or 0, hi or 1
						return lo + (hi - lo) * math.random()
					end
					return r
				end,
			},
			typeof = typeofX,
			task = {
				spawn = function(fn, ...)
					return M.scheduler:spawn(fn, ...)
				end,
				defer = function(fn, ...)
					return M.scheduler:delay(0, fn, ...)
				end,
				delay = function(t, fn, ...)
					return M.scheduler:delay(t, fn, ...)
				end,
				wait = function(t)
					return M.scheduler:wait(t)
				end,
			},
			os = {
				time = function()
					return M.time
				end,
				clock = function()
					return M.clock
				end,
				date = os.date,
			},
			warn = function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					parts[i] = tostring(select(i, ...))
				end
				local text = table.concat(parts, " ")
				table.insert(CM.warnings, text)
				signalOf(LogService, "MessageOut"):Fire(text, Enum.MessageType.MessageWarning)
			end,
			print = function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					parts[i] = tostring(select(i, ...))
				end
				table.insert(CM.prints, table.concat(parts, " "))
			end,
			require = function(target)
				if type(target) == "string" then
					local base = string.match(scriptNode.__path, "^(.*)/[^/]+$")
					local parts = {}
					for seg in string.gmatch(base, "[^/]+") do
						table.insert(parts, seg)
					end
					for seg in string.gmatch(string.gsub(target, "%.luau$", ""), "[^/]+") do
						if seg == ".." then
							table.remove(parts)
						elseif seg ~= "." then
							table.insert(parts, seg)
						end
					end
					local path = table.concat(parts, "/")
					if string.sub(base, 1, 1) == "/" then
						path = "/" .. path
					end
					return loadModule(path .. ".luau")
				elseif type(target) == "table" and rawget(target, "__path") then
					return loadModule(target.__path)
				end
				error("Attempted to call require with invalid argument(s).", 2)
			end,
			debug = debug,
		}
	end

	local function nodeFor(path)
		local function search(n)
			if rawget(n, "__path") == path then
				return n
			end
			for _, c in rawget(n, "__children") do
				local found = search(c)
				if found then
					return found
				end
			end
			return nil
		end
		return search(clientTree) or search(sharedTree)
	end

	loadModule = function(path)
		if cache[path] ~= nil then
			return cache[path]
		end
		local source = SOURCES[path] or error("client_mock: no source for " .. path)
		local fn = luau.load(source, { debugName = path, environment = makeEnv(nodeFor(path)) })
		local result = fn()
		cache[path] = if result == nil then false else result
		return result
	end

	-- ------------------------------------------------------------ public helpers
	function CM.require(relPath)
		return loadModule(root .. "/" .. relPath)
	end

	-- Starts the LocalScript and a 30 Hz Heartbeat/RenderStepped pump on the shared scheduler.
	function CM.start()
		local runService = service("RunService")
		M.spawn(function()
			while not CM.stopped do
				local dt = M.scheduler:wait(1 / 30)
				signalOf(runService, "Heartbeat"):Fire(dt)
				signalOf(runService, "RenderStepped"):Fire(dt)
			end
		end)
		M.spawn(function()
			loadModule(root .. "/src/client/Main.client.luau")
		end)
	end

	function CM.stop()
		CM.stopped = true
	end

	-- Runs fn as a client thread, then advances the clock so it can finish.
	function CM.run(fn, seconds)
		M.spawn(fn)
		M.advance(seconds or 0.5)
	end

	function CM.descendants(rootObj)
		return descendants(rootObj or playerGui)
	end

	function CM.visible(obj)
		local o = obj
		while o and o ~= playerGui do
			local s = st(o)
			if s.destroyed then
				return false
			end
			local vis = propInfo(s.class, "Visible") and o.Visible
			if vis == false then
				return false
			end
			if s.class == "ScreenGui" and o.Enabled == false then
				return false
			end
			o = s.parent
		end
		return o == playerGui
	end

	function CM.findAll(pred, rootObj)
		local out = {}
		for _, d in descendants(rootObj or playerGui) do
			if pred(d) then
				table.insert(out, d)
			end
		end
		return out
	end

	function CM.find(pred, rootObj)
		return CM.findAll(pred, rootObj)[1]
	end

	-- Visible GuiObject whose Text contains `text` (plain find).
	function CM.byText(text, className, rootObj)
		return CM.find(function(d)
			local s = st(d)
			return (className == nil or s.class == className)
				and propInfo(s.class, "Text") ~= nil
				and string.find(tostring(s.props.Text or ""), text, 1, true) ~= nil
				and CM.visible(d)
		end, rootObj)
	end

	function CM.buttons(rootObj)
		return CM.findAll(function(d)
			return st(d).class == "TextButton" and CM.visible(d) and d.Active
		end, rootObj)
	end

	-- "Clicks" a button: fires Activated (what the UI code listens to).
	function CM.click(button, seconds)
		assert(button, "CM.click: no button")
		signalOf(button, "Activated"):Fire()
		M.advance(seconds or 0.3)
	end

	function CM.text(obj)
		return tostring(st(obj).props.Text or "")
	end

	-- ---------------------------------------------------------------- UI snapshot export
	function CM.setViewport(w, h)
		I.setViewport(w, h)
		local sig = st(Workspace.CurrentCamera).propSignals.ViewportSize
		if sig then
			sig:Fire()
		end
	end

	local GuiDump = require("./mock/gui_dump")(st, propInfo, typeofX)
	-- Serializable tree of every ScreenGui in PlayerGui (+ viewport) for the PNG renderer.
	function CM.dumpGui()
		return GuiDump.dump(playerGui, I.viewport)
	end

	return CM
end

return ClientMock
