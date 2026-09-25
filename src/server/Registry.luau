--!nonstrict
-- Tiny service locator so services can reference each other lazily without require cycles.
local Registry = {}
local services = {}

function Registry.register(name: string, service)
	assert(services[name] == nil, "service already registered: " .. name)
	services[name] = service
	return service
end

function Registry.get(name: string)
	local s = services[name]
	assert(s, "service not registered yet: " .. name)
	return s
end

function Registry.startAll()
	for name, s in services do
		if type(s.Start) == "function" then
			local ok, err = pcall(s.Start, s)
			if not ok then
				warn("[Registry] " .. name .. ":Start failed: " .. tostring(err))
			end
		end
	end
end

return Registry
