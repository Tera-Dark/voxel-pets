--!nonstrict
-- Egg hatching with numeric odds disclosure (Roblox Paid Random Items policy) and PolicyService gating.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Pets = require(Shared.Config.Pets)
local Eggs = require(Shared.Config.Eggs)
local Rarities = require(Shared.Config.Rarities)
local Stages = require(Shared.Config.Stages)
local Hatch = require(Shared.Progression.Hatch)
local Rng = require(Shared.Combat.Rng)

local Registry = require(script.Parent.Parent.Registry)
local Remotes = require(script.Parent.Parent.Network.Remotes)

local HatchService = Registry.register("HatchService", {})

HatchService.MAX_MULTI = 3
local seeder = Random.new()

local function data(player)
	return Registry.get("DataService").Get(player)
end

-- Effective luck for the *next* hatch: consumable charges + permanent pass bonus.
function HatchService.CurrentLuck(player): number
	local d = data(player)
	local luck = 0
	if d.luckCharges > 0 then
		luck += d.luck
	end
	luck += Registry.get("MonetizationService").PassLuckBonus(player)
	return luck
end

function HatchService.IsEggAvailable(player, eggId: string): (boolean, string?)
	local egg = Eggs[eggId]
	if not egg then
		return false, "Unknown egg"
	end
	if egg.zone and not Stages.isZoneUnlocked(egg.zone, data(player).stages) then
		return false, "Reach " .. Stages.Zones[egg.zone].displayName .. " first"
	end
	if
		egg.paidRandomItem and Registry.get("MonetizationService").PaidRandomItemsRestricted(player)
	then
		return false, "Not available in your region"
	end
	return true, nil
end

function HatchService.GetOdds(player, eggId: string)
	local egg = Eggs[eggId]
	local luck = HatchService.CurrentLuck(player)
	local rows, byRarity = Hatch.disclosure(eggId, luck)
	local available, why = HatchService.IsEggAvailable(player, eggId)
	return {
		eggId = eggId,
		displayName = egg.displayName,
		price = egg.price,
		luck = luck,
		luckCharges = data(player).luckCharges,
		rows = rows,
		byRarity = byRarity,
		available = available,
		unavailableReason = why,
		paidRandomItem = egg.paidRandomItem == true,
	}
end

function HatchService.HatchEgg(player, eggId: string, count: number): (boolean, string?, any?)
	local d = data(player)
	local egg = Eggs[eggId]
	local available, why = HatchService.IsEggAvailable(player, eggId)
	if not available then
		return false, why
	end
	if count > 1 and not Registry.get("MonetizationService").HasPass(player, "TripleHatch") then
		return false, "Triple Hatch pass required"
	end
	if Registry.get("PetService").Count(player) + count > Registry.get("PetService").MAX_PETS then
		return false, "Pet storage full (dismantle some pets)"
	end
	local economy = Registry.get("EconomyService")
	if not economy.Spend(player, egg.price.currency, egg.price.amount * count, false) then
		return false, "Not enough " .. egg.price.currency
	end

	local results = {}
	local rng = Rng.new(seeder:NextInteger(1, 2 ^ 31 - 1))
	for _ = 1, count do
		local luck = HatchService.CurrentLuck(player)
		local petId, rarity = Hatch.roll(rng, eggId, luck)
		if d.luckCharges > 0 then
			d.luckCharges -= 1
		end
		local isNew = d.codex[petId] == nil
		local inst = Registry.get("PetService").Grant(player, petId, "Normal", false)
		table.insert(results, { uid = inst.uid, petId = petId, rarity = rarity, isNew = isNew })
		d.stats.hatches += 1
		if Rarities.Announce[rarity] then
			Registry.get("AnnouncementService").Broadcast(
				string.format(
					"%s hatched a %s %s!",
					player.DisplayName,
					rarity,
					Pets[petId].displayName
				),
				rarity
			)
		end
	end
	Registry.get("QuestService").Add(player, "hatches", count)
	Registry.get("DataService")
		.ReplicateKeys(player, { egg.price.currency, "pets", "nextUid", "codex", "stats", "luckCharges" })
	return true, nil, results
end

function HatchService.Start()
	Remotes.handle("GetHatchOdds", function(player, eggId)
		if not data(player) or not Eggs[eggId] then
			return false, "Bad request"
		end
		return true, nil, HatchService.GetOdds(player, eggId)
	end)
	Remotes.handle("HatchEgg", function(player, eggId, count)
		local n = Remotes.int(count, 1, HatchService.MAX_MULTI)
		if not data(player) or not Eggs[eggId] or not n then
			return false, "Bad request"
		end
		return HatchService.HatchEgg(player, eggId, n)
	end)
end

return HatchService
