--!nonstrict
-- Currency mutations. Every coin/gem/essence/shard/mark/ticket change goes through here so
-- prestige tracking, quest hooks and replication stay consistent.
local Registry = require(script.Parent.Parent.Registry)

local EconomyService = Registry.register("EconomyService", {})

EconomyService.CURRENCIES = {
	coins = true,
	gems = true,
	essence = true,
	shards = true,
	marks = true,
	medals = true,
	tickets = true,
}

local function data(player)
	return Registry.get("DataService").Get(player)
end

function EconomyService.Get(player, currency: string): number
	local d = data(player)
	return d and d[currency] or 0
end

function EconomyService.CanAfford(player, currency: string, amount: number): boolean
	return EconomyService.Get(player, currency) >= amount
end

-- Adds (amount may be fractional for production; stored floored).
function EconomyService.Add(player, currency: string, amount: number, replicate: boolean?)
	assert(EconomyService.CURRENCIES[currency], "unknown currency " .. tostring(currency))
	local d = data(player)
	if not d or amount <= 0 then
		return
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return
	end
	d[currency] += amount
	if currency == "coins" then
		d.prestige.coinsEarnedThisRun += amount
	end
	if replicate ~= false then
		Registry.get("DataService").ReplicateKeys(player, { currency })
	end
end

function EconomyService.AddMany(player, rewards, replicate: boolean?)
	local keys = {}
	for currency, amount in rewards do
		if EconomyService.CURRENCIES[currency] then
			EconomyService.Add(player, currency, amount, false)
			table.insert(keys, currency)
		end
	end
	if replicate ~= false and #keys > 0 then
		Registry.get("DataService").ReplicateKeys(player, keys)
	end
end

function EconomyService.Spend(
	player,
	currency: string,
	amount: number,
	replicate: boolean?
): boolean
	assert(EconomyService.CURRENCIES[currency], "unknown currency " .. tostring(currency))
	local d = data(player)
	if not d then
		return false
	end
	amount = math.floor(amount)
	if amount < 0 or d[currency] < amount then
		return false
	end
	d[currency] -= amount
	if replicate ~= false then
		Registry.get("DataService").ReplicateKeys(player, { currency })
	end
	return true
end

-- Spend several currencies atomically (all or nothing).
function EconomyService.SpendMany(player, costs): boolean
	for currency, amount in costs do
		if not EconomyService.CanAfford(player, currency, amount) then
			return false
		end
	end
	local keys = {}
	for currency, amount in costs do
		EconomyService.Spend(player, currency, amount, false)
		table.insert(keys, currency)
	end
	Registry.get("DataService").ReplicateKeys(player, keys)
	return true
end

return EconomyService
