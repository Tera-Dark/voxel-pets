--!nonstrict
-- Client-side remote wrappers. Nothing here throws or blocks forever:
--   Net.invoke(name, ...) -> ok, err, data   (times out after Net.TIMEOUT seconds)
--   Net.on(name, fn) -> connection | nil
--   Net.folder(timeout) -> the Remotes folder or nil (used by the boot screen)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Network = require(Shared.Network)

local Net = {}
Net.TIMEOUT = 20

local folder = nil
local cache = {}

function Net.folder(timeout: number?)
	if folder and folder.Parent then
		return folder
	end
	folder = ReplicatedStorage:FindFirstChild(Network.FOLDER)
		or ReplicatedStorage:WaitForChild(Network.FOLDER, timeout or 5)
	return folder
end

local function remote(name: string)
	local r = cache[name]
	if r and r.Parent then
		return r
	end
	local f = Net.folder(10)
	if not f then
		return nil
	end
	r = f:FindFirstChild(name) or f:WaitForChild(name, 5)
	if not r then
		warn("[Net] remote missing: " .. name)
	end
	cache[name] = r
	return r
end

function Net.invoke(name: string, ...)
	local r = remote(name)
	if not r then
		return false, "Connection error"
	end
	local args = table.pack(...)
	local done, results = false, nil
	task.spawn(function()
		results = table.pack(pcall(r.InvokeServer, r, table.unpack(args, 1, args.n)))
		done = true
	end)
	local started = os.clock()
	while not done do
		if os.clock() - started > Net.TIMEOUT then
			warn("[Net] " .. name .. " timed out after " .. Net.TIMEOUT .. "s")
			return false, "Server not responding"
		end
		task.wait()
	end
	if not results[1] then
		warn("[Net] " .. name .. " failed: " .. tostring(results[2]))
		return false, "Connection error"
	end
	return table.unpack(results, 2, results.n)
end

function Net.on(name: string, fn)
	local r = remote(name)
	if not r then
		return nil
	end
	return r.OnClientEvent:Connect(fn)
end

return Net
