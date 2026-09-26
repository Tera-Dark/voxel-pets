--!nonstrict
-- Boot & profile-loading robustness under a virtual-time scheduler (roblox_mock { scheduler = true }).
-- Each scenario reproduces a way a Roblox session can hang on "Loading your pets..." (first Studio
-- run, 2026-09-26) and asserts the server now recovers, or at least tells the client why.
local process = require("@lune/process")
local Mock = require("./roblox_mock")

local root = process.cwd:gsub("/$", "")

local failures, passes = 0, 0
local function check(cond, msg)
	if cond then
		passes += 1
	else
		failures += 1
		print("  FAIL: " .. msg)
	end
end

-- Boots a fresh server. `before(M)` runs first (configure knobs, pre-join players).
local function boot(opts, before)
	math.randomseed(20260926)
	local M = Mock.new(root, { scheduler = true, studio = opts.studio, placeId = opts.placeId })
	if before then
		before(M)
	end
	local Boot = M.load("src/server/Boot.luau")
	local result = {}
	M.spawn(function()
		result.state, result.errors = Boot.run({ world = false })
	end)
	return M, result
end

local function registry(M)
	return M.load("src/server/Registry.luau")
end

local function loadState(p)
	return p:GetAttribute("VP_LoadState")
end

print("1. player joined before the server finished booting")
do
	local p
	local M, r = boot({}, function(M)
		p = M.addPlayer(2001, "Early")
	end)
	M.advance(1)
	check(r.state == "ready", "boot ready: " .. tostring(r.state))
	check(M.attributes.VP_ServerState == "ready", "server state published")
	check(loadState(p) == "ready", "early player loaded (" .. tostring(loadState(p)) .. ")")
	check(#M.sent("ProfileDelta", p) >= 1, "early player received the profile")
	check(p:GetAttribute("VP_SaveMode") == "store", "published Studio + access -> real store")
	check(M.profileStore.stores[1] == "PlayerData_studio_v1", "Studio uses its own store")
	local ok, _, snap = M.invoke("GetProfile", p)
	check(ok and type(snap) == "table" and snap.pets ~= nil, "GetProfile snapshot")
end

print("2. unpublished place (PlaceId 0) -> offline profile, no hang")
do
	local M, r = boot({ placeId = 0 })
	M.advance(0.1)
	local p = M.join(2002, "Offline")
	M.advance(0.1)
	check(r.state == "ready", "boot ready")
	check(loadState(p) == "ready", "loaded (" .. tostring(loadState(p)) .. ")")
	check(p:GetAttribute("VP_SaveMode") == "offline", "offline save mode flagged for the client")
	check(#M.profileStore.stores == 0, "ProfileStore untouched")
	local Data = registry(M).get("DataService")
	Data.Get(p).coins = 777
	M.leave(p)
	local p2 = M.join(2002, "Offline")
	M.advance(0.1)
	local d2 = Data.Get(p2)
	check(d2 ~= nil and d2.coins == 777, "offline progress survives a rejoin within the session")
end

print("3. DataStore probe never finishes -> offline after the probe timeout")
do
	local M, r = boot({}, function(M)
		M.profileStore.DataStoreState = "NotReady"
	end)
	local p = M.join(2003, "Probe")
	M.advance(5)
	check(r.state == nil and M.attributes.VP_ServerState == "booting", "still probing at 5 s")
	check(M.attributes.VP_BootStage == "Ready", "boot stage visible to clients")
	M.advance(6)
	check(r.state == "ready", "boot finished after the probe timeout")
	M.advance(0.5)
	check(loadState(p) == "ready", "player loaded (" .. tostring(loadState(p)) .. ")")
	check(p:GetAttribute("VP_SaveMode") == "offline", "offline profile")
end

print("4. save session hangs in Studio -> waiting hint, then offline fallback")
do
	local M, _ = boot({}, function(M)
		M.profileStore.hang = true
	end)
	M.advance(0.1)
	local p = M.join(2004, "Hang")
	M.advance(3)
	check(loadState(p) == "loading", "loading at 3 s (" .. tostring(loadState(p)) .. ")")
	M.advance(5)
	check(
		loadState(p) == "waiting",
		"client told we are waiting (" .. tostring(loadState(p)) .. ")"
	)
	M.advance(15)
	check(
		loadState(p) == "ready",
		"fell back after the load timeout (" .. tostring(loadState(p)) .. ")"
	)
	check(p:GetAttribute("VP_SaveMode") == "offline", "fallback is an offline profile")
	check(#M.sent("ProfileDelta", p) >= 1, "profile replicated after fallback")
	local ended = M.profileStore.ended
	M.profileStore.hang = false
	M.advance(2)
	check(M.profileStore.ended == ended + 1, "late session released (no leaked session lock)")
end

print("5. live server: slow save keeps waiting, never an offline profile")
do
	local M, _ = boot({ studio = false }, function(M)
		M.profileStore.hang = true
	end)
	M.advance(0.1)
	local p = M.join(2005, "Live")
	M.advance(40)
	check(loadState(p) == "waiting", "waiting (" .. tostring(loadState(p)) .. ")")
	check(p:GetAttribute("VP_SaveMode") == nil, "no offline fallback in live servers")
	M.profileStore.hang = false
	M.advance(2)
	check(loadState(p) == "ready", "loaded once the session opens")
	check(p:GetAttribute("VP_SaveMode") == "store", "store mode")
	check(M.profileStore.stores[1] == "PlayerData_v1", "live store name")
end

print("6. a service that throws while loading does not take the server down")
do
	local M, r = boot({}, function(M)
		M.breakModule("src/server/Services/ArenaService.luau", "boom: arena exploded")
	end)
	M.advance(0.1)
	check(r.state == "degraded", "boot degraded (" .. tostring(r.state) .. ")")
	local errs = M.attributes.VP_BootErrors or ""
	check(errs:find("ArenaService", 1, true) ~= nil, "boot errors name the service: " .. errs)
	check(errs:find("ArenaFight", 1, true) ~= nil, "unhandled remotes reported")
	local p = M.join(2006, "Degraded")
	M.advance(0.5)
	check(loadState(p) == "ready", "players still load")
	local okStage = M.invoke("StartStage", p, 1, 1)
	check(okStage, "other systems keep working (stage 1-1)")
	local okArena, errArena = M.invoke("ArenaGetOpponents", p)
	check(
		not okArena and errArena == "Unavailable right now",
		"broken feature answers instead of hanging: " .. tostring(errArena)
	)
end

print("7. MemoryStore unavailable -> arena falls back to bots")
do
	local M, r = boot({}, function(M)
		M.services.MemoryStoreService.GetSortedMap = function()
			error("MemoryStore is not available")
		end
	end)
	M.advance(0.1)
	check(r.state == "ready", "boot ready")
	local p = M.join(2007, "Arena")
	M.advance(0.5)
	local ok, err, offer = M.invoke("ArenaGetOpponents", p)
	check(ok and offer and #offer.opponents == 3, "3 bot opponents: " .. tostring(err))
	local okLb, _, rows = M.invoke("ArenaLeaderboard", p)
	check(okLb and type(rows) == "table", "leaderboard still answers")
end

print("8. duplicate PlayerAdded -> exactly one session")
do
	local M, _ = boot({}, function(M)
		M.profileStore.hang = true
	end)
	M.advance(0.1)
	local p = M.join(2008, "Twice")
	M.fireAdded(p)
	M.advance(0.1)
	check(M.profileStore.started == 1, "one StartSessionAsync (" .. M.profileStore.started .. ")")
	M.profileStore.hang = false
	M.advance(2)
	check(loadState(p) == "ready", "loaded")
end

print("9. server warnings reach developer clients (DevLog)")
do
	local M, _ = boot({})
	M.advance(0.1)
	local p = M.join(2009, "Dev")
	M.advance(0.1)
	check(p:GetAttribute("VP_Dev") == true, "Studio players are developers")
	M.services.LogService.MessageOut:Fire(
		"[Test] something broke",
		Mock.Enum.MessageType.MessageError
	)
	M.services.LogService.MessageOut:Fire(
		"[Test] something broke",
		Mock.Enum.MessageType.MessageError
	)
	M.services.LogService.MessageOut:Fire("plain print", Mock.Enum.MessageType.MessageOutput)
	local sent = M.sent("DevLog", p)
	check(#sent == 2, "errors forwarded, prints ignored (" .. #sent .. ")")
	local entry = sent[#sent] and sent[#sent][1] and sent[#sent][1][1]
	check(entry and entry.count == 2 and entry.kind == "error", "duplicates are counted")
	local late = M.join(2010, "LateDev")
	M.advance(0.1)
	check(#M.sent("DevLog", late) >= 1, "late developer gets the history")
end

print(string.format("\n%d passed, %d failed", passes, failures))
if failures > 0 then
	process.exit(1)
end
