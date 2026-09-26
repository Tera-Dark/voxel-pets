--!nonstrict
-- New-player tutorial (4 short steps, ~2-3 minutes). profile.tutorialStep = number of completed
-- steps (0..COUNT); SKIPPED marks a skipped tutorial. Step 1 (starter choice) is recorded by the
-- server when the player confirms a partner; steps 2+ are derived from profile state, so the
-- server validates progress and pays the reward without trusting the client.
local Tutorial = {}

-- (Levelling with coins is taught contextually afterwards: battle XP already levels the pet
-- after the first win, and the next coin level costs more than the first battles pay.)
Tutorial.STEPS = {
	{ id = "starter", goal = "Choose your partner", hint = "Pick the pet you like best." },
	{ id = "battle", goal = "Win your first battle", hint = "Tap BATTLE, then FIGHT." },
	{ id = "hatch", goal = "Hatch your free egg", hint = "Open Hatch and tap Hatch x1 (FREE)." },
	{ id = "stage2", goal = "Win stage 1-2", hint = "Beat the next stage to finish the tutorial." },
}
Tutorial.COUNT = #Tutorial.STEPS
-- All Rare, so the choice is about element/role (Fire > Grass > Water > Fire), not power.
Tutorial.STARTERS = { "Emberfox", "Tidefrog", "Mossback" }
Tutorial.SKIPPED = 99
Tutorial.REWARD = { gems = 50 }

-- Is step i (2..COUNT) satisfied by the current profile state?
function Tutorial.stepDone(profile, i: number): boolean
	local stages = profile.stages or {}
	if i == 2 then
		return (stages["1-1"] or 0) > 0
	elseif i == 3 then
		return ((profile.stats and profile.stats.hatches) or 0) >= 1
	elseif i == 4 then
		return (stages["1-2"] or 0) > 0
	end
	return false
end

-- Completed-step count after applying everything the profile already satisfies. Monotonic;
-- steps complete in order (anything done early counts the moment its step is reached).
function Tutorial.progress(profile): number
	local step = profile.tutorialStep or 0
	if step >= Tutorial.COUNT or step < 1 then
		return step -- finished / skipped, or still waiting for the starter choice
	end
	while step < Tutorial.COUNT and Tutorial.stepDone(profile, step + 1) do
		step += 1
	end
	return step
end

function Tutorial.isActive(profile): boolean
	return profile ~= nil and (profile.tutorialStep or 0) < Tutorial.COUNT
end

-- The step the player is on (table from STEPS) and its index, or nil when finished.
function Tutorial.current(profile)
	if not Tutorial.isActive(profile) then
		return nil, nil
	end
	local i = (profile.tutorialStep or 0) + 1
	return Tutorial.STEPS[i], i
end

return Tutorial
