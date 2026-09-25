--!nonstrict
-- Prints a human-readable log of one battle.
-- usage: lune run tools/sim_replay -- [petA] [petB] [seed] [relicA,relicB,...]
local process = require("@lune/process")
local Builder = require("../src/shared/Combat/Builder")
local Simulator = require("../src/shared/Combat/Simulator")

local args = {}
for _, a in process.args do
	if a ~= "--" then
		table.insert(args, a)
	end
end
local petA, petB = args[1] or "Emberfox", args[2] or "ThornbackBoar"
local seed = tonumber(args[3]) or 42
local relics = {}
if args[4] then
	for id in string.gmatch(args[4], "[^,]+") do
		table.insert(relics, id)
	end
end

local a = Builder.build({ petId = petA, level = 10 }, { side = "A", relics = relics })
local b = Builder.build({ petId = petB, level = 10 }, { side = "B" })
local names = { [a.uid] = a.name, [b.uid] = b.name }

print(
	string.format(
		"%s (Lv%d %s %s, power %d, relics: %s)",
		a.name,
		a.level,
		a.element,
		a.role,
		a.power,
		#relics > 0 and table.concat(relics, ", ") or "none"
	)
)
print(
	string.format(
		"   vs %s (Lv%d %s %s, power %d)   seed=%d",
		b.name,
		b.level,
		b.element,
		b.role,
		b.power,
		seed
	)
)
print(string.rep("-", 78))

local result = Simulator.run({ seed = seed, teamA = { a }, teamB = { b } })
for _, e in result.events do
	local src, dst = names[e.src] or "", names[e.dst] or ""
	local line
	if e.type == "Damage" then
		local tags = {}
		if e.skill then
			table.insert(tags, "skill")
		end
		if e.crit then
			table.insert(tags, "CRIT")
		end
		if e.element then
			table.insert(tags, string.format("x%.2f elem", e.element))
		end
		if e.interrupt then
			table.insert(tags, "INTERRUPT")
		end
		if e.status then
			table.insert(tags, e.status)
		end
		if e.absorbed > 0 then
			table.insert(tags, e.absorbed .. " absorbed")
		end
		line = string.format(
			"%-14s hits %-14s for %4d  (hp %4d)  %s",
			src ~= "" and src or e.status,
			dst,
			e.amount,
			e.hp,
			table.concat(tags, ", ")
		)
	elseif e.type == "Skill" then
		line = string.format("%-14s casts %s", src, e.skill)
	elseif e.type == "ChargeStart" then
		line = string.format("%-14s starts charging %s (%.1fs)", src, e.skill, e.castTime)
	elseif e.type == "Interrupt" then
		line = string.format("%-14s INTERRUPTS %s", src, dst)
	elseif e.type == "Status" then
		line = string.format("%-14s gets %s x%d", dst, e.status, e.stacks)
	elseif e.type == "Heal" then
		line = string.format("%-14s heals %d (hp %d)", dst, e.amount, e.hp)
	elseif e.type == "Shield" then
		line = string.format("%-14s shield +%d (total %d)", dst, e.amount, e.total)
	elseif e.type == "Death" then
		line = string.format("%-14s is defeated", dst)
	elseif e.type == "Revive" then
		line = string.format("%-14s REVIVES with %d hp", dst, e.hp)
	elseif e.type == "BattleEnd" then
		line = string.format(
			"== winner: %s  duration %.1fs%s",
			e.winner,
			e.duration,
			e.timedOut and " (timeout)" or ""
		)
	elseif
		e.type == "Miss"
		or e.type == "StatusEnd"
		or e.type == "ShieldExpired"
		or e.type == "Cleanse"
		or e.type == "BattleStart"
	then
		line = nil
	end
	if line then
		print(string.format("[%5.1fs] %s", e.t, line))
	end
end
print(
	string.format(
		"damage A=%d B=%d, skills A=%d B=%d, interrupts=%d",
		result.summary.damage.A,
		result.summary.damage.B,
		result.summary.skillCasts.A,
		result.summary.skillCasts.B,
		result.summary.interrupts
	)
)
