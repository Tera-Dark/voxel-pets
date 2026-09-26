--!nonstrict
-- Battle replay flow: a BattleResult from the server opens the Battle screen, plays the events on
-- the 3D stage (BattleStage) and offers result actions (Next / Retry / back to the mode's
-- screen). A failing replay closes cleanly with a toast instead of leaving the player stuck.
local BattleFlow = {}

-- deps: { ctx, Screens, BattleStage, Battle (screen module), Stages (screen module),
--         StagesConfig, Net, State, Theme, step }
function BattleFlow.start(deps)
	local ctx, Screens, BattleStage = deps.ctx, deps.Screens, deps.BattleStage
	local Battle, Stages, StagesConfig = deps.Battle, deps.Stages, deps.StagesConfig
	local Net, State, Theme, step = deps.Net, deps.State, deps.Theme, deps.step

	local function resultActions(payload)
		local actions = {}
		local function closeBattle()
			BattleStage.stop()
			Screens.close()
		end
		if payload.mode == "Stage" and Stages.current then
			local zone, stage = Stages.current()
			local won = payload.winner == "A"
			if won then
				table.insert(actions, {
					text = "Next",
					color = Theme.Colors.good,
					fn = function()
						BattleStage.stop()
						local nextStage, nextZone = stage + 1, zone
						if nextStage > StagesConfig.STAGES_PER_ZONE then
							nextStage, nextZone = 1, zone + 1
						end
						Screens.open("Stages", { zone = nextZone, stage = nextStage })
					end,
				})
			end
			table.insert(actions, {
				text = won and "Again" or "Retry",
				color = Theme.Colors.info,
				fn = function()
					local ok, err = Net.invoke("StartStage", zone, stage)
					if not ok then
						ctx.toast(err, "bad")
						closeBattle()
					end
				end,
			})
			table.insert(actions, {
				text = "Stages",
				color = Theme.Colors.panelLight,
				fn = function()
					BattleStage.stop()
					Screens.open("Stages", { zone = zone, stage = stage })
				end,
			})
		elseif payload.mode == "Arena" then
			table.insert(actions, {
				text = "Arena",
				color = Theme.Colors.info,
				fn = function()
					BattleStage.stop()
					Screens.open("Arena")
				end,
			})
		elseif payload.mode == "Expedition" then
			table.insert(actions, {
				text = "Map",
				color = Theme.Colors.info,
				fn = function()
					BattleStage.stop()
					Screens.open("Expedition")
				end,
			})
		end
		table.insert(actions, { text = "Close", color = Theme.Colors.panelLight, fn = closeBattle })
		return actions
	end

	local function playBattle(payload)
		if type(payload) ~= "table" or not payload.teamA or not payload.teamB then
			return
		end
		local settings = (State.profile and State.profile.settings) or {}
		Screens.open("Battle")
		local battleUi = nil
		local ctl = BattleStage.play(payload, {
			speed = settings.battleSpeed or 1,
			onHp = function(uid, hp, shield)
				if battleUi then
					battleUi.onHp(uid, hp, shield)
				end
			end,
			onLog = function(text, kind)
				if battleUi then
					battleUi.onLog(text, kind)
				end
			end,
			onFinished = function()
				if battleUi then
					battleUi.showResult()
				end
			end,
		})
		battleUi = Battle.show(ctx, payload, ctl, resultActions(payload))
		if settings.autoSkip then
			task.defer(function()
				ctl.skip()
			end)
		end
	end

	step("battle playback", function()
		Net.on("BattleResult", function(payload)
			if not step("battle", playBattle, payload) then
				BattleStage.stop()
				Screens.close()
				ctx.toast("The battle replay failed to load", "bad")
			end
		end)
	end)
end

return BattleFlow
