--!nonstrict
-- Minimal Roblox API mock so server services can be smoke-tested in Lune.
-- Not a faithful engine: just enough surface (services, signals, remotes, ProfileStore) to run
-- the game logic end to end. Anything outside this surface should be exercised in Studio.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Mock = {}

-- ---------------------------------------------------------------- signals
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end
function Signal:Connect(fn)
	table.insert(self.handlers, fn)
	local conn = { Connected = true }
	function conn.Disconnect()
		conn.Connected = false
		local i = table.find(self.handlers, fn)
		if i then
			table.remove(self.handlers, i)
		end
	end
	return conn
end
function Signal:Fire(...)
	for _, fn in table.clone(self.handlers) do
		fn(...)
	end
end
Mock.Signal = Signal

-- ---------------------------------------------------------------- instance tree from disk
-- Builds { Name, Parent, children..., __path } nodes mirroring src/ so `script.Parent.X` works.
local function node(name, path, parent)
	local n = { Name = name, __path = path, Parent = parent, __children = {} }
	return setmetatable(n, {
		__index = function(t, k)
			if type(k) == "string" and k:sub(1, 2) == "__" then
				return nil
			end
			local child = rawget(t, "__children")[k]
			if child then
				return child
			end
			error(("mock instance %s has no child %s"):format(name, tostring(k)))
		end,
	})
end

local function buildTree(dir, name, parent)
	local n = node(name, nil, parent)
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			n.__children[entry] = buildTree(full, entry, n)
		elseif entry:match("%.luau$") then
			local modName =
				entry:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
			local child = node(modName, full, n)
			n.__children[modName] = child
		end
	end
	return n
end

-- ---------------------------------------------------------------- Roblox-ish globals
local function enumProxy()
	return setmetatable({}, {
		__index = function(_, enumName)
			return setmetatable({}, {
				__index = function(_, item)
					return { Name = item, EnumType = enumName }
				end,
			})
		end,
	})
end

local function instanceNew(className)
	local inst = { ClassName = className, Parent = nil, __children = {} } -- Name set by caller (hooked)
	if className == "BindableEvent" then
		inst.Event = Signal.new()
		function inst:Fire(...)
			self.Event:Fire(...)
		end
	elseif className == "RemoteEvent" then
		inst.sent = {}
		function inst:FireClient(player, ...)
			table.insert(self.sent, { player = player, args = table.pack(...) })
		end
		function inst:FireAllClients(...)
			table.insert(self.sent, { player = nil, args = table.pack(...) })
		end
	elseif className == "RemoteFunction" then
		inst.OnServerInvoke = nil
	end
	return inst
end

function Mock.newPlayer(userId, name)
	local p =
		{ UserId = userId, Name = name, DisplayName = name, kicked = nil, ClassName = "Player" }
	function p:Kick(reason)
		self.kicked = reason or "kicked"
	end
	return p
end

-- ---------------------------------------------------------------- fake ProfileStore
local function deepCopy(t)
	local out = {}
	for k, v in t do
		out[k] = type(v) == "table" and deepCopy(v) or v
	end
	return out
end
local function reconcile(target, template)
	for k, v in template do
		if target[k] == nil then
			target[k] = type(v) == "table" and deepCopy(v) or v
		elseif type(v) == "table" and type(target[k]) == "table" and #v == 0 then
			reconcile(target[k], v)
		end
	end
end

local function fakeProfileStore()
	local PS = { saved = {} }
	function PS.New(storeName, template)
		local store = { Name = storeName, template = template }
		store.Mock = store
		function store:StartSessionAsync(key)
			local data = PS.saved[key] and deepCopy(PS.saved[key]) or deepCopy(template)
			local profile = { Data = data, Key = key, OnSessionEnd = Signal.new(), active = true }
			function profile:AddUserId() end
			function profile:Reconcile()
				reconcile(self.Data, template)
			end
			function profile:IsActive()
				return self.active
			end
			function profile:EndSession()
				self.active = false
				PS.saved[key] = deepCopy(self.Data)
				self.OnSessionEnd:Fire()
			end
			return profile
		end
		return store
	end
	return PS
end

-- ---------------------------------------------------------------- environment / loader
function Mock.new(rootDir)
	local M = {}
	local shared = buildTree(rootDir .. "/src/shared", "Shared", nil)
	local server = buildTree(rootDir .. "/src/server", "Server", nil)

	M.players = {}
	M.time = os.time()
	M.startTime = M.time
	M.remotes = { functions = {}, events = {} }
	M.profileStore = fakeProfileStore()

	local Players = {
		PlayerAdded = Signal.new(),
		PlayerRemoving = Signal.new(),
		Name = "Players",
	}
	function Players:GetPlayers()
		return table.clone(M.players)
	end
	function Players:GetPlayerByUserId(id)
		for _, p in M.players do
			if p.UserId == id then
				return p
			end
		end
		return nil
	end

	local ReplicatedStorage = { Name = "ReplicatedStorage", Shared = shared }
	shared.Parent = ReplicatedStorage

	local services = {
		Players = Players,
		ReplicatedStorage = ReplicatedStorage,
		RunService = {
			IsStudio = function()
				return true
			end,
		},
		TextService = {
			FilterStringAsync = function(_, text)
				return {
					GetNonChatStringForBroadcastAsync = function()
						return text
					end,
				}
			end,
		},
		MemoryStoreService = {
			GetSortedMap = function()
				return {
					SetAsync = function() end,
					GetRangeAsync = function()
						return {}
					end,
				}
			end,
		},
		MessagingService = {
			PublishAsync = function() end,
			SubscribeAsync = function() end,
		},
		MarketplaceService = {
			PromptGamePassPurchaseFinished = Signal.new(),
			UserOwnsGamePassAsync = function()
				return false
			end,
		},
		PolicyService = {
			GetPolicyInfoForPlayerAsync = function()
				return { ArePaidRandomItemsRestricted = M.paidRandomRestricted == true }
			end,
		},
		ServerScriptService = { Name = "ServerScriptService" },
	}
	M.services = services

	local game = { JobId = "mock-job" }
	function game:GetService(name)
		return services[name] or error("mock has no service " .. name)
	end

	local cache = {}
	local loadModule

	local function makeEnv(scriptNode)
		local env
		env = {
			game = game,
			script = scriptNode,
			Enum = enumProxy(),
			Instance = {
				new = function(className)
					local inst = instanceNew(className)
					if className == "RemoteFunction" or className == "RemoteEvent" then
						-- registered by name once Name is assigned; we hook via __newindex
						return setmetatable(inst, {
							__newindex = function(t, k, v)
								rawset(t, k, v)
								if k == "Name" then
									if className == "RemoteFunction" then
										M.remotes.functions[v] = t
									else
										M.remotes.events[v] = t
									end
								end
							end,
						})
					end
					return inst
				end,
			},
			Random = {
				new = function(seed)
					local r = { seed = seed }
					function r:NextInteger(lo, hi)
						return math.random(lo, hi)
					end
					function r:NextNumber(lo, hi)
						lo = lo or 0
						hi = hi or 1
						return lo + (hi - lo) * math.random()
					end
					return r
				end,
			},
			task = {
				spawn = function(fn, ...)
					local ok, err = pcall(fn, ...)
					if not ok and not tostring(err):find("mock: task.wait") then
						warn("[mock task.spawn] " .. tostring(err))
					end
				end,
				defer = function(fn, ...)
					local ok, err = pcall(fn, ...)
					if not ok then
						warn("[mock task.defer] " .. tostring(err))
					end
				end,
				delay = function(_, fn, ...)
					local ok, err = pcall(fn, ...)
					if not ok then
						warn("[mock task.delay] " .. tostring(err))
					end
				end,
				wait = function()
					error("mock: task.wait in a loop is not supported (loops are skipped)")
				end,
			},
			os = {
				time = function()
					return M.time
				end,
				clock = function()
					return os.clock() + (M.time - M.startTime) -- advance() moves the monotonic clock too
				end,
				date = os.date,
			},
			require = function(target)
				local path
				if type(target) == "string" then
					local base = scriptNode.__path:match("^(.*)/[^/]+$")
					local rel = target:gsub("%.luau$", "")
					local parts = {}
					for seg in string.gmatch(base, "[^/]+") do
						table.insert(parts, seg)
					end
					for seg in string.gmatch(rel, "[^/]+") do
						if seg == ".." then
							table.remove(parts)
						elseif seg ~= "." then
							table.insert(parts, seg)
						end
					end
					path = "/" .. table.concat(parts, "/") .. ".luau"
					if base:sub(1, 1) ~= "/" then
						path = path:sub(2)
					end
				elseif type(target) == "table" and target.__path then
					path = target.__path
				elseif type(target) == "table" and target.__fake then
					return target.__fake
				else
					error("mock require: unsupported target " .. tostring(target))
				end
				return loadModule(path)
			end,
		}
		return env
	end

	local function nodeFor(path)
		-- find the tree node with this path (for `script`)
		local function search(n)
			if n.__path == path then
				return n
			end
			for _, c in n.__children do
				local found = search(c)
				if found then
					return found
				end
			end
			return nil
		end
		return search(shared) or search(server) or node(path:match("([^/]+)%.luau$"), path, nil)
	end

	loadModule = function(path)
		if cache[path] ~= nil then
			return cache[path]
		end
		local source = fs.readFile(path)
		local fn = luau.load(source, { debugName = path, environment = makeEnv(nodeFor(path)) })
		local result = fn()
		cache[path] = result == nil and false or result
		return result
	end

	-- Vendor/ProfileStore is replaced by the fake (the real one needs DataStoreService).
	server.__children.Vendor = node("Vendor", nil, server)
	server.__children.Vendor.__children.ProfileStore =
		{ __fake = M.profileStore, Name = "ProfileStore" }

	function M.load(relPath)
		return loadModule(rootDir .. "/" .. relPath)
	end

	-- Simulates a player joining: fires PlayerAdded so DataService loads a profile.
	function M.join(userId, name)
		local p = Mock.newPlayer(userId, name)
		p.Parent = Players
		table.insert(M.players, p)
		Players.PlayerAdded:Fire(p)
		return p
	end
	function M.leave(p)
		Players.PlayerRemoving:Fire(p)
		p.Parent = nil
		local i = table.find(M.players, p)
		if i then
			table.remove(M.players, i)
		end
	end

	-- Invokes a RemoteFunction as the given player.
	function M.invoke(name, player, ...)
		local rf = M.remotes.functions[name]
		assert(rf, "no remote function " .. name)
		assert(rf.OnServerInvoke, "remote " .. name .. " has no handler")
		return rf.OnServerInvoke(player, ...)
	end

	-- Last N payloads sent through a RemoteEvent to a player.
	function M.sent(name, player)
		local re = M.remotes.events[name]
		local out = {}
		for _, msg in re.sent do
			if msg.player == player or msg.player == nil then
				table.insert(out, msg.args)
			end
		end
		return out
	end

	function M.advance(seconds)
		M.time += seconds
	end

	return M
end

return Mock
