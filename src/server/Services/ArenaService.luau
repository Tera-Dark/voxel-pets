--!nonstrict
-- Asynchronous PvP: fight snapshots of other players' defense pets (MemoryStore index by power),
-- with generated bots as a fallback so the arena always has opponents. Elo for the attacker only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Stages = require(Shared.Config.Stages)
local Eggs = require(Shared.Config.Eggs)
local PetInstance = require(Shared.Progression.PetInstance)
local Builder = require(Shared.Combat.Builder)

local Registry = require(script.Parent.Parent.Registry)
local Remotes = require(script.Parent.Parent.Network.Remotes)

local ArenaService = Registry.register("ArenaService", {})

local INDEX_TTL = 7 * 24 * 3600
local OFFER_TTL = 300
local K_FACTOR = 32
local REWARDS = { win = { medals = 10 }, loss = { medals = 2 } }

local POWER_MAP, RATING_MAP = "ArenaByPower_v1", "ArenaByRating_v1"
-- MemoryStore handles are created lazily under pcall: GetSortedMap can throw where MemoryStore is
-- unavailable (e.g. unpublished Studio places), and a module-level throw used to abort server boot.
-- nil handle => every caller falls back to bots / an empty leaderboard.
local maps = {}
local function sortedMap(name: string)
	local m = maps[name]
	if m == nil then
		local ok, res = pcall(MemoryStoreService.GetSortedMap, MemoryStoreService, name)
		if not ok then
			warn("[Arena] MemoryStore unavailable, using bots: " .. tostring(res))
		end
		m = if ok and res then res else false
		maps[name] = m
	end
	return m or nil
end
local offers = {} -- [player] = { list = {...}, expiresAt = t }
local seeder = Random.new()

local function data(player)
	return Registry.get("DataService").Get(player)
end

-- ---------------------------------------------------------------- snapshots
local function snapshotFor(player)
	local d = data(player)
	local inst = d.pets[d.team["1"]]
	if not inst then
		return nil
	end
	local copy = table.clone(inst)
	copy.nickname = nil
	return {
		userId = player.UserId,
		name = player.DisplayName,
		rating = d.arena.rating,
		power = PetInstance.power(inst, Registry.get("PetService").GlobalMult(player)),
		globalMult = Registry.get("PetService").GlobalMult(player),
		pet = copy,
		updatedAt = os.time(),
	}
end

function ArenaService.Publish(player)
	local snap = snapshotFor(player)
	if not snap then
		return
	end
	local key = tostring(player.UserId)
	local byPower, byRating = sortedMap(POWER_MAP), sortedMap(RATING_MAP)
	if byPower then
		pcall(byPower.SetAsync, byPower, key, snap, INDEX_TTL, snap.power)
	end
	if byRating then
		pcall(
			byRating.SetAsync,
			byRating,
			key,
			{ name = snap.name, rating = snap.rating, power = snap.power },
			INDEX_TTL,
			snap.rating
		)
	end
end

-- ---------------------------------------------------------------- bots
local BOT_NAMES = {
	"CubeKnight",
	"PixelPaws",
	"BlockyBee",
	"VoxelViper",
	"MossyMike",
	"EmberElla",
	"TideTom",
	"GlitchGoat",
}

local function botFor(power: number, index: number)
	-- pick a species from any zone egg pool, then find a level whose power lands near the target
	local pool = {}
	for _, egg in Eggs do
		for _, list in egg.pool do
			for _, id in list do
				if
					Pets[id].rarity == "Rare"
					or Pets[id].rarity == "Uncommon"
					or Pets[id].rarity == "Epic"
				then
					table.insert(pool, id)
				end
			end
		end
	end
	table.sort(pool)
	local petId = pool[seeder:NextInteger(1, #pool)]
	local inst = PetInstance.new(petId, "bot", 0)
	local target = power * seeder:NextNumber(0.9, 1.15)
	for level = 1, 100 do
		inst.level = level
		inst.evolution = level > 60 and 3 or (level > 30 and 2 or 1)
		if PetInstance.power(inst) >= target then
			break
		end
	end
	return {
		userId = -index,
		name = BOT_NAMES[((index - 1) % #BOT_NAMES) + 1],
		rating = 900 + seeder:NextInteger(0, 300),
		power = PetInstance.power(inst),
		globalMult = 1,
		pet = inst,
		bot = true,
	}
end

-- ---------------------------------------------------------------- matchmaking
function ArenaService.GetOpponents(player)
	local d = data(player)
	local mine = snapshotFor(player)
	if not mine then
		return false, "No pet in your team"
	end
	local candidates = {}
	local byPower = sortedMap(POWER_MAP)
	local ok, items = pcall(function()
		if not byPower then
			error("MemoryStore unavailable")
		end
		return byPower:GetRangeAsync(
			Enum.SortDirection.Ascending,
			30,
			{ sortKey = math.floor(mine.power * 0.75) },
			{ sortKey = math.ceil(mine.power * 1.35) }
		)
	end)
	if ok and type(items) == "table" then
		for _, item in items do
			local v = item.value
			if type(v) == "table" and v.userId ~= player.UserId and v.pet and Pets[v.pet.petId] then
				table.insert(candidates, v)
			end
		end
	end
	-- shuffle and take 3, fill with bots
	local list = {}
	while #list < 3 and #candidates > 0 do
		table.insert(list, table.remove(candidates, seeder:NextInteger(1, #candidates)))
	end
	local botIndex = 0
	while #list < 3 do
		botIndex += 1
		table.insert(list, botFor(mine.power, botIndex))
	end
	offers[player] = { list = list, expiresAt = os.clock() + OFFER_TTL }
	local public = {}
	for i, o in list do
		public[i] = {
			name = o.name,
			rating = o.rating,
			power = o.power,
			petId = o.pet.petId,
			level = o.pet.level,
			variant = o.pet.variant,
			bot = o.bot == true,
		}
	end
	return true,
		nil,
		{
			opponents = public,
			rating = d.arena.rating,
			wins = d.arena.wins,
			losses = d.arena.losses,
		}
end

local function elo(ra, rb, won)
	local expected = 1 / (1 + 10 ^ ((rb - ra) / 400))
	return math.floor(ra + K_FACTOR * ((won and 1 or 0) - expected) + 0.5)
end

function ArenaService.Fight(player, index: number): (boolean, string?, any?)
	local d = data(player)
	local offer = offers[player]
	if not offer or os.clock() > offer.expiresAt or not offer.list[index] then
		return false, "Pick an opponent first"
	end
	local opponent = offer.list[index]
	offers[player] = nil
	local PetService = Registry.get("PetService")
	local teamA = PetService.BuildTeam(player)
	if #teamA == 0 then
		return false, "No pet in your team"
	end
	local teamB = {
		Builder.build(opponent.pet, {
			side = "B",
			slot = 1,
			globalMult = opponent.globalMult or 1,
			displayName = opponent.name .. "'s " .. Pets[opponent.pet.petId].displayName,
		}),
	}
	local BattleService = Registry.get("BattleService")
	local result, payload = BattleService.Run(
		teamA,
		teamB,
		{ mode = "Arena", opponent = opponent.name, bot = opponent.bot == true }
	)
	local won = result.winner == "A"
	BattleService.RecordOutcome(player, won)
	local before = d.arena.rating
	d.arena.rating = math.max(0, elo(before, opponent.rating, won))
	if won then
		d.arena.wins += 1
	else
		d.arena.losses += 1
	end
	local rewards = table.clone(won and REWARDS.win or REWARDS.loss)
	rewards.ratingDelta = d.arena.rating - before
	rewards.coins = math.floor(
		Stages.rewards(1, 5).coins
			* (won and 3 or 1)
			* Registry.get("PrestigeService").ProductionMult(player)
	)
	Registry.get("EconomyService")
		.AddMany(player, { medals = rewards.medals, coins = rewards.coins }, false)
	Registry.get("QuestService").Add(player, "arenaFights", 1)
	payload.rewards = rewards
	Registry.get("DataService").ReplicateKeys(player, { "arena", "medals", "coins", "stats" })
	BattleService.Send(player, payload)
	task.spawn(ArenaService.Publish, player)
	return true, nil, { winner = result.winner, rewards = rewards, rating = d.arena.rating }
end

function ArenaService.Leaderboard()
	local byRating = sortedMap(RATING_MAP)
	local ok, items = pcall(function()
		if not byRating then
			error("MemoryStore unavailable")
		end
		return byRating:GetRangeAsync(Enum.SortDirection.Descending, 50)
	end)
	local rows = {}
	if ok and type(items) == "table" then
		for i, item in items do
			local v = item.value
			if type(v) == "table" then
				rows[i] = { rank = i, name = v.name, rating = v.rating, power = v.power }
			end
		end
	end
	return rows
end

function ArenaService.Start()
	Registry.get("DataService").PlayerLoaded:Connect(function(player)
		task.delay(3, ArenaService.Publish, player)
	end)
	Registry.get("DataService").PlayerUnloading:Connect(function(player)
		offers[player] = nil
		pcall(ArenaService.Publish, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		offers[player] = nil
	end)

	Remotes.handle("ArenaGetOpponents", function(player)
		if not data(player) then
			return false, "Bad request"
		end
		return ArenaService.GetOpponents(player)
	end)
	Remotes.handle("ArenaFight", function(player, index)
		local i = Remotes.int(index, 1, 3)
		if not data(player) or not i then
			return false, "Bad request"
		end
		return ArenaService.Fight(player, i)
	end)
	Remotes.handle("ArenaLeaderboard", function(player)
		if not data(player) then
			return false, "Bad request"
		end
		return true, nil, ArenaService.Leaderboard()
	end)
end

return ArenaService
