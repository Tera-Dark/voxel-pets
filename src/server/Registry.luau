--!nonstrict
-- Tiny service locator so services can reference each other lazily without require cycles.
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

function Registry.startAll()
	for _, name in order do -- registration (require) order, so DataService starts first
		local s = services[name]
		if type(s.Start) == "function" then
			local ok, err = pcall(s.Start, s)
			if not ok then
				warn("[Registry] " .. name .. ":Start failed: " .. tostring(err))
			end
		end
	end
end

return Registry
