--!nonstrict
-- Game features shown in the HUD dock: grouping, dock order and progressive unlock rules.
-- Pure data + pure functions (client gating / goal tracker, unit-tested under Lune).
--
-- unlock = nil            always available
-- unlock = { stage = k }  stage k ("zone-stage") cleared
-- unlock = { hatches = n } hatched at least n eggs
-- dock = false            not a dock tile (Stages: the big BATTLE button is its entry point)
local Stages = require("./Stages")

local Features = {}

-- Dock order = this order (grouped); unlock order = by requirement rank (see rank()).
Features.LIST = {
	{
		id = "Stages",
		label = "Battle",
		group = "adventure",
		icon = "sword",
		dock = false,
		blurb = "Fight wild pets and push through the zones.",
	},
	{
		id = "Expedition",
		label = "Expedition",
		group = "adventure",
		icon = "portal",
		unlock = { stage = "1-5" },
		blurb = "Roguelike runs: pick relics, beat the floor boss, earn marks.",
	},
	{
		id = "Arena",
		label = "Arena",
		group = "adventure",
		icon = "trophy",
		unlock = { stage = "1-10" },
		blurb = "Battle other players' pets for medals and rating.",
	},
	{
		id = "Pets",
		label = "Pets",
		group = "pets",
		icon = "paw",
		blurb = "Level up, evolve and pick your active pet.",
	},
	{
		id = "Hatch",
		label = "Hatch",
		group = "pets",
		icon = "egg",
		unlock = { stage = "1-1" },
		blurb = "Open eggs to find new pets. Your first egg is free!",
	},
	{
		id = "Codex",
		label = "Codex",
		group = "pets",
		icon = "book",
		unlock = { hatches = 1 },
		blurb = "Every species you discover gives a permanent bonus.",
	},
	{
		id = "Camp",
		label = "Camp",
		group = "base",
		icon = "tent",
		unlock = { stage = "1-3" },
		blurb = "Idle pets earn coins and XP - even while you are offline.",
	},
	{
		id = "Prestige",
		label = "Prestige",
		group = "base",
		icon = "star",
		unlock = { stage = "2-10" },
		blurb = "Reset your run for permanent multipliers.",
	},
	{
		id = "Quests",
		label = "Quests",
		group = "more",
		icon = "scroll",
		unlock = { stage = "1-2" },
		blurb = "Daily quests and login rewards.",
	},
	{
		id = "Shop",
		label = "Shop",
		group = "more",
		icon = "bag",
		unlock = { stage = "1-2" },
		blurb = "Spend gems on boosts, tickets and more.",
	},
}

Features.GROUP_ORDER = { "adventure", "pets", "base", "more" }

Features.ById = {}
for i, f in Features.LIST do
	f.order = i
	Features.ById[f.id] = f
end

local function stageIndex(key: string): number
	local zone, stage = string.match(key, "^(%d+)%-(%d+)$")
	return (tonumber(zone) - 1) * Stages.STAGES_PER_ZONE + tonumber(stage)
end

-- Progress rank of a feature's requirement (0 = always); hatching sits between 1-1 and 1-2.
function Features.rank(id: string): number
	local f = Features.ById[id]
	local u = f and f.unlock
	if not u then
		return 0
	elseif u.stage then
		return stageIndex(u.stage)
	elseif u.hatches then
		return 1.5
	end
	return math.huge
end

function Features.isUnlocked(profile, id: string): boolean
	local f = Features.ById[id]
	if not f then
		return false
	end
	local u = f.unlock
	if not u then
		return true
	end
	if not profile then
		return false
	end
	if u.stage then
		return ((profile.stages or {})[u.stage] or 0) > 0
	elseif u.hatches then
		return ((profile.stats and profile.stats.hatches) or 0) >= u.hatches
	end
	return false
end

-- Short player-facing requirement, e.g. "Clear stage 1-3".
function Features.requirement(id: string): string
	local f = Features.ById[id]
	local u = f and f.unlock
	if not u then
		return ""
	elseif u.stage then
		return "Clear stage " .. u.stage
	elseif u.hatches then
		return if u.hatches == 1 then "Hatch your first egg" else "Hatch " .. u.hatches .. " eggs"
	end
	return "Locked"
end

-- Unlocked features in dock order.
function Features.unlocked(profile)
	local out = {}
	for _, f in Features.LIST do
		if Features.isUnlocked(profile, f.id) then
			table.insert(out, f)
		end
	end
	return out
end

-- The locked feature that unlocks next (lowest requirement rank), or nil when all are open.
function Features.nextLocked(profile)
	local best, bestRank = nil, math.huge
	for _, f in Features.LIST do
		if not Features.isUnlocked(profile, f.id) then
			local r = Features.rank(f.id)
			if r < bestRank then
				best, bestRank = f, r
			end
		end
	end
	return best
end

return Features
