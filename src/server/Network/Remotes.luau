--!nonstrict
-- Creates remotes from the shared Network contract and wraps handlers with
-- type validation helpers, rate limiting and error isolation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Network = require(ReplicatedStorage.Shared.Network)

local Remotes = {}
local folder = Instance.new("Folder")
folder.Name = Network.FOLDER

local functions, events = {}, {}
for _, name in Network.Functions do
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = folder
	functions[name] = rf
end
for _, name in Network.Events do
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = folder
	events[name] = re
end
folder.Parent = ReplicatedStorage

-- ---------------------------------------------------------------- rate limiting
local WINDOW = 10
local buckets = {} -- [player] = { [name] = { count, resetAt } }

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

local function allowed(player, name): boolean
	local limit = Network.RATE_LIMITS[name] or Network.RATE_LIMITS.default
	local now = os.clock()
	buckets[player] = buckets[player] or {}
	local b = buckets[player][name]
	if not b or now >= b.resetAt then
		b = { count = 0, resetAt = now + WINDOW }
		buckets[player][name] = b
	end
	b.count += 1
	return b.count <= limit
end

-- ---------------------------------------------------------------- handlers
-- handler(player, ...) -> ok: boolean, err: string?, payload: any?
function Remotes.handle(name: string, handler)
	local rf = functions[name]
	assert(rf, "unknown remote function " .. name)
	rf.OnServerInvoke = function(player, ...)
		if not allowed(player, name) then
			return false, "Slow down"
		end
		local results = table.pack(pcall(handler, player, ...))
		if not results[1] then
			warn(
				string.format(
					"[Remotes] %s failed for %s: %s",
					name,
					player.Name,
					tostring(results[2])
				)
			)
			return false, "Server error"
		end
		return table.unpack(results, 2, results.n)
	end
end

function Remotes.fire(name: string, player, ...)
	local re = events[name]
	assert(re, "unknown remote event " .. name)
	re:FireClient(player, ...)
end

function Remotes.fireAll(name: string, ...)
	events[name]:FireAllClients(...)
end

-- ---------------------------------------------------------------- validators
function Remotes.int(v, lo: number?, hi: number?): number?
	if type(v) ~= "number" or v ~= v or v % 1 ~= 0 then
		return nil
	end
	if (lo and v < lo) or (hi and v > hi) then
		return nil
	end
	return v
end

function Remotes.str(v, maxLen: number?): string?
	if type(v) ~= "string" or #v == 0 or (maxLen and #v > maxLen) then
		return nil
	end
	return v
end

function Remotes.strList(v, maxLen: number): { string }?
	if type(v) ~= "table" or #v == 0 or #v > maxLen then
		return nil
	end
	local out = {}
	for i, s in ipairs(v) do
		if type(s) ~= "string" then
			return nil
		end
		out[i] = s
	end
	return out
end

return Remotes
