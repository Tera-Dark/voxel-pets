--!nonstrict
-- Client-side remote wrappers. invoke() never throws: returns ok, err, data.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Network = require(Shared.Network)

local Net = {}
local folder = ReplicatedStorage:WaitForChild(Network.FOLDER, 30)
assert(folder, "Remotes folder missing")

local cache = {}
local function remote(name)
	local r = cache[name]
	if not r then
		r = folder:WaitForChild(name, 10)
		assert(r, "remote missing: " .. name)
		cache[name] = r
	end
	return r
end

function Net.invoke(name: string, ...)
	local results = table.pack(pcall(remote(name).InvokeServer, remote(name), ...))
	if not results[1] then
		warn("[Net] " .. name .. " failed: " .. tostring(results[2]))
		return false, "Connection error"
	end
	return table.unpack(results, 2, results.n)
end

function Net.on(name: string, fn)
	return remote(name).OnClientEvent:Connect(fn)
end

return Net
