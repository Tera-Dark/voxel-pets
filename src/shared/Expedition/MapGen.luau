--!nonstrict
-- Seeded expedition floor generator (Slay-the-Spire style branching columns).
-- Pure: same seed + floor + talents -> same map on server, client and in tests.
local Rng = require("../Combat/Rng")
local Stages = require("../Config/Stages")

local MapGen = {}

MapGen.COLUMNS = 10
MapGen.LANES = 3

local KIND_WEIGHTS = { Battle = 45, Elite = 12, Event = 15, Shop = 10, Campfire = 8, Treasure = 10 }

local function weightedPick(rng, weights)
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = rng:next() * total
	for kind, w in weights do
		roll -= w
		if roll <= 0 then
			return kind
		end
	end
	return "Battle"
end

local function pickKind(rng, col, hasShop, hasCampfire, extraTreasure)
	if col == 1 then
		return "Battle"
	elseif col == MapGen.COLUMNS then
		return "Boss"
	elseif col == MapGen.COLUMNS - 1 then
		return "Campfire" -- rest before the boss
	end
	local weights = table.clone(KIND_WEIGHTS)
	if col < 3 then
		weights.Elite = 0
	end
	if col < 4 then
		weights.Shop = 0
	end
	if hasShop then
		weights.Shop = weights.Shop / 3
	end
	if hasCampfire then
		weights.Campfire = weights.Campfire / 2
	end
	weights.Treasure += 5 * (extraTreasure or 0)
	return weightedPick(rng, weights)
end

-- floor -> which zone's pool the enemies come from (floors beyond zone count reuse the last zone)
function MapGen.zoneForFloor(floor: number): number
	return math.min(floor, #Stages.Zones)
end

-- opts: { extraTreasure = number? }
function MapGen.generate(seed: number, floor: number, opts)
	opts = opts or {}
	local rng = Rng.new(seed + floor * 7919)
	local zone = Stages.Zones[MapGen.zoneForFloor(floor)]
	local columns, nodes = {}, {}
	local hasShop, hasCampfire = false, false
	local nextId = 0

	for col = 1, MapGen.COLUMNS do
		local count = (col == 1 or col == MapGen.COLUMNS) and 1 or rng:int(2, 3)
		local lanes = {}
		if count == 1 then
			lanes = { 2 }
		elseif count == 2 then
			lanes = rng:chance(0.5) and { 1, 2 } or { 2, 3 }
			if rng:chance(0.3) then
				lanes = { 1, 3 }
			end
		else
			lanes = { 1, 2, 3 }
		end
		columns[col] = {}
		for _, lane in lanes do
			nextId += 1
			local kind = pickKind(rng, col, hasShop, hasCampfire, opts.extraTreasure)
			if kind == "Shop" then
				hasShop = true
			elseif kind == "Campfire" and col < MapGen.COLUMNS - 1 then
				hasCampfire = true
			end
			local node = { id = nextId, col = col, lane = lane, kind = kind, next = {} }
			if kind == "Battle" then
				node.enemy = zone.pool[rng:int(1, #zone.pool)]
			elseif kind == "Elite" then
				node.enemy = zone.elite
			elseif kind == "Boss" then
				node.enemy = zone.boss
			end
			nodes[nextId] = node
			table.insert(columns[col], node)
		end
	end

	-- edges: connect to next column nodes within one lane of distance; guarantee connectivity
	for col = 1, MapGen.COLUMNS - 1 do
		local nextCol = columns[col + 1]
		for _, node in columns[col] do
			for _, cand in nextCol do
				if math.abs(cand.lane - node.lane) <= 1 then
					table.insert(node.next, cand.id)
				end
			end
			if #node.next == 0 then
				-- nearest lane
				local best, bestDist = nil, math.huge
				for _, cand in nextCol do
					local d = math.abs(cand.lane - node.lane)
					if d < bestDist then
						best, bestDist = cand, d
					end
				end
				table.insert(node.next, best.id)
			end
		end
		-- every node in next column needs at least one predecessor
		for _, cand in nextCol do
			local hasPrev = false
			for _, node in columns[col] do
				if table.find(node.next, cand.id) then
					hasPrev = true
					break
				end
			end
			if not hasPrev then
				local best, bestDist = nil, math.huge
				for _, node in columns[col] do
					local d = math.abs(cand.lane - node.lane)
					if d < bestDist then
						best, bestDist = node, d
					end
				end
				table.insert(best.next, cand.id)
			end
		end
	end

	return {
		seed = seed,
		floor = floor,
		zone = zone.id,
		columns = columns,
		nodes = nodes,
		startId = columns[1][1].id,
		bossId = columns[MapGen.COLUMNS][1].id,
	}
end

-- Validation used by tests and by the server before trusting a stored map.
function MapGen.validate(map): (boolean, string?)
	if not map or not map.nodes or not map.columns then
		return false, "missing fields"
	end
	if #map.columns ~= MapGen.COLUMNS then
		return false, "column count"
	end
	local start = map.nodes[map.startId]
	if not start or start.kind ~= "Battle" then
		return false, "start must be a battle"
	end
	if map.nodes[map.bossId].kind ~= "Boss" then
		return false, "last must be boss"
	end
	-- reachability from start to boss
	local seen = { [map.startId] = true }
	local frontier = { map.startId }
	while #frontier > 0 do
		local id = table.remove(frontier)
		for _, nid in map.nodes[id].next do
			if not seen[nid] then
				seen[nid] = true
				table.insert(frontier, nid)
			end
		end
	end
	for id, node in map.nodes do
		if not seen[id] then
			return false, "unreachable node " .. id .. " (" .. node.kind .. ")"
		end
		if node.kind ~= "Boss" and #node.next == 0 then
			return false, "dead end " .. id
		end
	end
	return true, nil
end

return MapGen
