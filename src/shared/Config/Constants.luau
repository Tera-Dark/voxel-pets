--!nonstrict
-- Global tuning constants shared by server, client and the offline simulator.
local Constants = {
	-- Team layout: data structures support 5 slots from day one; only ACTIVE_TEAM_SLOTS are used.
	MAX_TEAM_SLOTS = 5,
	ACTIVE_TEAM_SLOTS = 1, -- P0..P2: 1v1

	-- Combat simulation
	TICK_SECONDS = 0.1,
	MAX_BATTLE_SECONDS = 120,
	CRIT_MULT = 1.75,
	INTERRUPT_MULT = 1.5,
	INTERRUPT_WINDOW = 0.8, -- interrupt allowed when enemy charge progress >= 80%
	ELEMENT_ADVANTAGE = 1.3,
	ELEMENT_DISADVANTAGE = 0.77,
	DAMAGE_VARIANCE = 0.15, -- +-15%; keeps close fights from being fully predetermined
	MITIGATION_K = 1.5, -- mitigation = DEF / (DEF + K * attackerATK)  (scale-invariant)
	DEFAULT_TRIGGER_MAX_WAIT = 4, -- conditional triggers fire anyway after waiting this long
	-- Sudden death: after ENRAGE_START_SECONDS all damage dealt gains +ENRAGE_STEP_MULT every ENRAGE_STEP_SECONDS.
	ENRAGE_START_SECONDS = 25,
	ENRAGE_STEP_SECONDS = 5,
	ENRAGE_STEP_MULT = 0.25,

	-- Progression
	LEVEL_STAT_PER_LEVEL = 0.05,
	STAR_STAT_PER_STAR = 0.2,
	MAX_STARS = 6,
	EVOLUTION_MULT = { 1.0, 1.6, 2.5 },
	EVOLUTION_LEVEL_CAP = { 30, 60, 100 },

	-- PvE scaling
	ZONE_STAT_MULT = 2.0, -- 2.5 -> 2.0 (2026-09-26 pve_curve pass: zone walls were 2x the in-zone growth)
	STAGE_STAT_MULT = 1.10, -- 1.08 -> 1.10
	WILD_STAT_MULT = 1.4, -- wild pets are mostly Common; this keeps them relevant vs Rare starters
	ELITE_STAT_MULT = 1.0, -- elites get their edge from skills + HP overrides, not raw stat inflation
	BOSS_STAT_MULT = 1.0, -- bosses: Common rarity + HP override + Hardening/BossQuake + this
	STAGES_PER_ZONE = 10,
}

return Constants
