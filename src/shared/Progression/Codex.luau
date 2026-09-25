--!nonstrict
-- Collection codex: registering species/variants grants permanent account-wide stat multipliers.
local Pets = require("../Config/Pets")
local Stages = require("../Config/Stages")

local Codex = {}

Codex.SPECIES_BONUS = 0.003
Codex.VARIANT_BONUS = 0.002
Codex.ZONE_COMPLETE_BONUS = 0.03

-- codex: { [petId] = { [variant] = true } }
function Codex.register(codex, petId: string, variant: string?): boolean
	variant = variant or "Normal"
	codex[petId] = codex[petId] or {}
	if codex[petId][variant] then
		return false
	end
	codex[petId][variant] = true
	return true
end

function Codex.zoneSpecies(zone: number)
	local z = Stages.Zones[zone]
	local list = table.clone(z.pool)
	table.insert(list, z.elite)
	table.insert(list, z.boss)
	return list
end

function Codex.isZoneComplete(codex, zone: number): boolean
	for _, petId in Codex.zoneSpecies(zone) do
		if not codex[petId] then
			return false
		end
	end
	return true
end

function Codex.summary(codex)
	local species, variants = 0, 0
	for _, variantsSet in codex do
		species += 1
		for v in variantsSet do
			if v ~= "Normal" then
				variants += 1
			end
		end
	end
	local zonesComplete = 0
	for zone = 1, #Stages.Zones do
		if Codex.isZoneComplete(codex, zone) then
			zonesComplete += 1
		end
	end
	local total = 0
	for _ in Pets do
		total += 1
	end
	return {
		species = species,
		variants = variants,
		zonesComplete = zonesComplete,
		totalSpecies = total,
	}
end

function Codex.bonusMult(codex): number
	local s = Codex.summary(codex)
	return 1
		+ s.species * Codex.SPECIES_BONUS
		+ s.variants * Codex.VARIANT_BONUS
		+ s.zonesComplete * Codex.ZONE_COMPLETE_BONUS
end

return Codex
