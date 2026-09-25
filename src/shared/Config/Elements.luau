--!nonstrict
-- Six elements. Fire > Grass > Water > Fire; Light <> Dark; Neutral has no matchups.
local Constants = require("./Constants")

local Elements = {}

Elements.List = { "Fire", "Water", "Grass", "Light", "Dark", "Neutral" }

-- attacker -> set of elements it is strong against
Elements.StrongAgainst = {
	Fire = { Grass = true },
	Grass = { Water = true },
	Water = { Fire = true },
	Light = { Dark = true },
	Dark = { Light = true },
	Neutral = {},
}

-- RGB tuples (0-255); client converts to Color3. Kept engine-agnostic so the module runs in Lune.
Elements.ColorRGB = {
	Fire = { 255, 96, 48 },
	Water = { 64, 160, 255 },
	Grass = { 96, 200, 80 },
	Light = { 255, 232, 128 },
	Dark = { 150, 90, 220 },
	Neutral = { 200, 200, 200 },
}

function Elements.isValid(element: string): boolean
	return Elements.StrongAgainst[element] ~= nil
end

-- Returns "advantage" | "disadvantage" | "neutral" for attacker vs defender.
function Elements.relation(attacker: string, defender: string): string
	if Elements.StrongAgainst[attacker][defender] then
		return "advantage"
	elseif Elements.StrongAgainst[defender][attacker] then
		return "disadvantage"
	end
	return "neutral"
end

-- elementMode: "normal" | "invert" (Inversion Prism) | "neutralize" (Element Ward)
-- Modes belong to the *owner* of the relic; both sides' modes are considered.
function Elements.multiplier(
	attacker: string,
	defender: string,
	attackerMode: string?,
	defenderMode: string?
): number
	local relation = Elements.relation(attacker, defender)
	local invert = (attackerMode == "invert") ~= (defenderMode == "invert")
	if invert then
		if relation == "advantage" then
			relation = "disadvantage"
		elseif relation == "disadvantage" then
			relation = "advantage"
		end
	end

	if relation == "advantage" then
		local mult = Constants.ELEMENT_ADVANTAGE
		if defenderMode == "neutralize" then
			mult = 1 + (mult - 1) * 0.5 -- 1.5 -> 1.25
		end
		return mult
	elseif relation == "disadvantage" then
		local mult = Constants.ELEMENT_DISADVANTAGE
		if attackerMode == "neutralize" then
			mult = 1 - (1 - mult) * 0.5 -- 0.67 -> 0.835
		end
		return mult
	end
	return 1
end

return Elements
