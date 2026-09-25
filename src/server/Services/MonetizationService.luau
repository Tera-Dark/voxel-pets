--!nonstrict
-- Gamepasses, developer products (gem packs), gem shop, daily login, PolicyService gating.
-- All Roblox product IDs are placeholders (0 = disabled) until the experience is published.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)

local Registry = require(script.Parent.Parent.Registry)
local Remotes = require(script.Parent.Parent.Network.Remotes)

local MonetizationService = Registry.register("MonetizationService", {})

-- ---------------------------------------------------------------- catalog
MonetizationService.Passes = {
	VIP = {
		id = 0,
		displayName = "VIP",
		description = "+10% coins, 12h offline cap, VIP chat tag.",
	},
	TripleHatch = { id = 0, displayName = "Triple Hatch", description = "Hatch 3 eggs at once." },
	LuckyCharm = {
		id = 0,
		displayName = "Lucky Charm",
		description = "+25% Rare+ odds on every egg, forever (shown in odds).",
	},
}
MonetizationService.PASS_LUCK = 0.25

MonetizationService.Products = { -- developer products -> gems
	GemsSmall = { id = 0, displayName = "Handful of Gems", gems = 100 },
	GemsMedium = { id = 0, displayName = "Bag of Gems", gems = 550 },
	GemsLarge = { id = 0, displayName = "Chest of Gems", gems = 1200 },
}

-- Items bought with gems (gems are Robux-purchasable => no random outcomes here except eggs,
-- which are handled by HatchService with full odds disclosure).
MonetizationService.GemShop = {
	{
		id = "LuckPotion",
		displayName = "Luck Potion",
		description = "+50% Rare+ odds for your next 10 hatches.",
		gems = 50,
	},
	{
		id = "Tickets3",
		displayName = "3 Expedition Tickets",
		description = "Instant expedition entries.",
		gems = 30,
	},
	{
		id = "Essence10",
		displayName = "Essence x10",
		description = "Evolution material.",
		gems = 40,
	},
	{
		id = "CoinPouch",
		displayName = "Coin Pouch",
		description = "Coins scaled to your furthest zone.",
		gems = 60,
	},
}

MonetizationService.DailyRewards = { -- 7-day cycle
	{ coins = 200 },
	{ gems = 10 },
	{ coins = 500 },
	{ essence = 5 },
	{ gems = 20 },
	{ tickets = 2 },
	{ gems = 40, coins = 1000 },
}

-- ---------------------------------------------------------------- state
local policyCache = {} -- [player] = { restricted = bool }

local function data(player)
	return Registry.get("DataService").Get(player)
end

function MonetizationService.HasPass(player, passName: string): boolean
	local d = data(player)
	return d ~= nil and d.passes[passName] == true
end

function MonetizationService.PassLuckBonus(player): number
	return MonetizationService.HasPass(player, "LuckyCharm") and MonetizationService.PASS_LUCK or 0
end

function MonetizationService.PaidRandomItemsRestricted(player): boolean
	local cached = policyCache[player]
	if cached then
		return cached.restricted
	end
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	-- Conservative: if the policy lookup fails, treat paid random items as restricted.
	local restricted = true
	if ok and type(info) == "table" then
		restricted = info.ArePaidRandomItemsRestricted == true
	end
	policyCache[player] = { restricted = restricted }
	return restricted
end

local function refreshPasses(player)
	local d = data(player)
	if not d then
		return
	end
	for name, pass in MonetizationService.Passes do
		if pass.id > 0 then
			local ok, owns = pcall(
				MarketplaceService.UserOwnsGamePassAsync,
				MarketplaceService,
				player.UserId,
				pass.id
			)
			if ok and owns then
				d.passes[name] = true
			end
		end
	end
end

-- ---------------------------------------------------------------- gem shop
function MonetizationService.BuyWithGems(player, itemId: string): (boolean, string?, any?)
	local d = data(player)
	local item = nil
	for _, it in MonetizationService.GemShop do
		if it.id == itemId then
			item = it
		end
	end
	if not item then
		return false, "Unknown item"
	end
	local economy = Registry.get("EconomyService")
	if not economy.CanAfford(player, "gems", item.gems) then
		return false, "Not enough gems"
	end
	local granted = {}
	if itemId == "LuckPotion" then
		if d.luckCharges > 0 then
			return false, "A Luck Potion is already active"
		end
		d.luck = 0.5
		d.luckCharges = 10
		granted.luckCharges = 10
	elseif itemId == "Tickets3" then
		granted.tickets = 3
	elseif itemId == "Essence10" then
		granted.essence = 10
	elseif itemId == "CoinPouch" then
		local zone = 1
		for z = #Stages.Zones, 1, -1 do
			if Stages.isZoneUnlocked(z, d.stages) then
				zone = z
				break
			end
		end
		granted.coins = Stages.rewards(zone, 5).coins * 40
	end
	economy.Spend(player, "gems", item.gems, false)
	economy.AddMany(player, granted, false)
	Registry.get("DataService")
		.ReplicateKeys(player, { "gems", "coins", "tickets", "essence", "luck", "luckCharges" })
	return true, nil, granted
end

-- ---------------------------------------------------------------- daily login
function MonetizationService.ClaimDaily(player): (boolean, string?, any?)
	local d = data(player)
	local today = os.date("!%Y-%m-%d")
	if d.stats.lastDailyClaim == today then
		return false, "Already claimed today"
	end
	local yesterday = os.date("!%Y-%m-%d", os.time() - 86400)
	if d.stats.lastDailyClaim == yesterday then
		d.stats.loginStreak += 1
	else
		d.stats.loginStreak = 1
	end
	d.stats.lastDailyClaim = today
	local day = ((d.stats.loginStreak - 1) % #MonetizationService.DailyRewards) + 1
	local reward = table.clone(MonetizationService.DailyRewards[day])
	Registry.get("EconomyService").AddMany(player, reward, false)
	Registry.get("DataService")
		.ReplicateKeys(player, { "stats", "coins", "gems", "essence", "tickets" })
	reward.day = day
	reward.streak = d.stats.loginStreak
	return true, nil, reward
end

-- ---------------------------------------------------------------- receipts
local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local d = data(player)
	if not d then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = tostring(receipt.PurchaseId)
	if d.purchases[key] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	for _, product in MonetizationService.Products do
		if product.id == receipt.ProductId and product.id > 0 then
			Registry.get("EconomyService").Add(player, "gems", product.gems)
			d.purchases[key] = true
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	warn("[Monetization] unknown product id " .. tostring(receipt.ProductId))
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationService.Start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local d = data(player)
		if not d then
			return
		end
		for name, pass in MonetizationService.Passes do
			if pass.id == passId and pass.id > 0 then
				d.passes[name] = true
				Registry.get("DataService").ReplicateKeys(player, { "passes" })
			end
		end
	end)
	Registry.get("DataService").PlayerLoaded:Connect(function(player)
		task.spawn(refreshPasses, player)
		task.spawn(MonetizationService.PaidRandomItemsRestricted, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		policyCache[player] = nil
	end)

	Remotes.handle("GetShop", function(player)
		if not data(player) then
			return false, "Bad request"
		end
		return true,
			nil,
			{
				passes = MonetizationService.Passes,
				products = MonetizationService.Products,
				gemShop = MonetizationService.GemShop,
				daily = MonetizationService.DailyRewards,
				paidRandomItemsRestricted = MonetizationService.PaidRandomItemsRestricted(player),
			}
	end)
	Remotes.handle("BuyWithGems", function(player, itemId)
		if not data(player) or not Remotes.str(itemId, 32) then
			return false, "Bad request"
		end
		return MonetizationService.BuyWithGems(player, itemId)
	end)
	Remotes.handle("ClaimDaily", function(player)
		if not data(player) then
			return false, "Bad request"
		end
		return MonetizationService.ClaimDaily(player)
	end)
end

return MonetizationService
