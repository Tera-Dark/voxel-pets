--!nonstrict
-- Tiny service locator so services can reference each other lazily without require cycles.
-- Lifecycle (driven by Boot): require all -> Start() all (wire remotes/signals) -> Ready() all
-- (begin work that needs every service listening, e.g. DataService loading players).
local Registry = {}
local services = {}
local order = {}

function Registry.register(name: string, service)
	assert(services[name] == nil, "service already registered: " .. name)
	services[name] = service
	table.insert(order, name)
	return service
end

function Registry.get(name: string)
	local s = services[name]
	assert(s, "service not registered yet: " .. name)
	return s
end

function Registry.has(name: string): boolean
	return services[name] ~= nil
end

local function traceback(err)
	return tostring(err) .. "\n" .. debug.traceback(nil, 2)
end

-- Calls service[method] in registration order; one failure never stops the others.
local function runPhase(method: string, onError)
	for _, name in order do
		local s = services[name]
		if type(s[method]) == "function" then
			local ok, err = xpcall(s[method], traceback, s)
			if not ok then
				if onError then
					onError(name .. ":" .. method, err)
				else
					warn("[Registry] " .. name .. ":" .. method .. " failed: " .. tostring(err))
				end
			end
		end
	end
end

function Registry.startAll(onError)
	runPhase("Start", onError)
end

function Registry.readyAll(onError)
	runPhase("Ready", onError)
end

return Registry
