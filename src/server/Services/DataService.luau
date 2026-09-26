--!nonstrict
-- Player profiles. Other services read/write profile.Data through DataService.Get(player) and
-- call Replicate()/ReplicateKeys() after changes.
--
-- Save modes (decided once in Ready(), exposed as DataService.Mode and player attr VP_SaveMode):
--   "store"   ProfileStore, session-locked. Always in live servers; in Studio only when DataStore
--             access is confirmed (published place + "Enable Studio Access to API Services"),
--             using a separate Studio store so tests never touch live saves.
--   "offline" in-memory profile: Studio without DataStore access (e.g. an unpublished .rbxl).
--             The game is fully playable, progress is not saved; the client shows a banner.
--
-- Loading never hangs silently (this used to leave clients on "Loading your pets..." forever):
--   * the Studio DataStore probe and every session start are bounded by timeouts; Studio falls
--     back to an offline profile, live servers tell the client they are still waiting;
--   * a player is never loaded twice (PlayerAdded + GetPlayers race under deferred signals);
--   * players only start loading in Ready(), after every service has subscribed to PlayerLoaded.
-- Load hooks (DataService.OnLoad) run synchronously, in order, BEFORE the first replication:
-- data prepared at load (starter pet, daily resets, ...) must be in that first snapshot. Under
-- Roblox's default deferred SignalBehavior, PlayerLoaded handlers only run after the snapshot has
-- been sent (a starter granted there once never reached the client: "No active pet"), so a
-- second full snapshot is deferred until they are done.
-- Per-player progress is visible to the client as attribute VP_LoadState:
--   "loading" -> ("waiting") -> "ready" | "failed".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ProfileStore = require(script.Parent.Parent.Vendor.ProfileStore)
local Remotes = require(script.Parent.Parent.Network.Remotes)
local Registry = require(script.Parent.Parent.Registry)
local DataTemplate = require(ReplicatedStorage.Shared.DataTemplate)

local DataService = Registry.register("DataService", {})

DataService.STORE_NAME = "PlayerData_v1"
DataService.STUDIO_STORE_NAME = "PlayerData_studio_v1"
DataService.ACCESS_PROBE_TIMEOUT = 10 -- s to wait for ProfileStore's Studio DataStore probe
DataService.LOAD_TIMEOUT = 20 -- s before a Studio session falls back to an offline profile
DataService.SLOW_LOAD_HINT = 6 -- s before the client is told we are still waiting
DataService.Mode = nil

-- Template = data fields only (strip helper keys).
local template = {}
for k, v in DataTemplate do
	if k ~= "PUBLIC_KEYS" and k ~= "MAX_TEAM_SLOTS" then
		template[k] = v
	end
end

local function deepCopy(t)
	local out = {}
	for k, v in t do
		out[k] = if type(v) == "table" then deepCopy(v) else v
	end
	return out
end

-- Fills keys missing from target (recursing into dictionary tables), like Profile:Reconcile().
local function reconcile(target, source)
	for k, v in source do
		if target[k] == nil then
			target[k] = if type(v) == "table" then deepCopy(v) else v
		elseif type(v) == "table" and type(target[k]) == "table" and #v == 0 then
			reconcile(target[k], v)
		end
	end
end

local profiles = {} -- [player] = profile
local loading = {} -- [player] = true while a session is being opened
local hydrating = {} -- [player] = true while load hooks run (replication held back)
local loadHooks = {} -- { { name, fn(player, data) } }
local store = nil
local offlineSaves = {} -- [key] = data; survives leave/rejoin within one Studio session

local loaded = Instance.new("BindableEvent")
DataService.PlayerLoaded = loaded.Event -- (player, data)
local unloading = Instance.new("BindableEvent")
DataService.PlayerUnloading = unloading.Event -- (player, data)

-- Registers a synchronous load hook (see header). Hooks must not yield.
function DataService.OnLoad(name: string, fn)
	table.insert(loadHooks, { name = name, fn = fn })
end

local function setAttr(player, name, value)
	pcall(player.SetAttribute, player, name, value)
end

local function migrate(data)
	-- schemaVersion 1: nothing yet. Add `if data.schemaVersion < 2 then ... end` steps here.
	data.schemaVersion = DataTemplate.schemaVersion
end

-- ---------------------------------------------------------------- sessions
local function offlineSession(key: string)
	local data = offlineSaves[key]
	if not data then
		data = deepCopy(template)
		offlineSaves[key] = data
	end
	local ended = Instance.new("BindableEvent")
	local profile = { Data = data, OnSessionEnd = ended.Event, Offline = true }
	function profile.AddUserId() end
	function profile.Reconcile(self)
		reconcile(self.Data, template)
	end
	function profile.EndSession() end
	return profile
end

-- Opens a ProfileStore session without ever blocking forever. Returns profile (or nil), mode.
local function storeSession(player: Player, key: string)
	local settled, result = false, nil
	task.spawn(function()
		local ok, profile = pcall(store.StartSessionAsync, store, key, {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
		if not ok then
			warn("[DataService] StartSessionAsync failed: " .. tostring(profile))
		end
		if settled then -- the watchdog already gave up on this session: release it
			if ok and profile then
				profile:EndSession()
			end
			return
		end
		result = if ok then profile else nil
		settled = true
	end)
	local started, hinted = os.clock(), false
	while not settled do
		local waited = os.clock() - started
		if not hinted and waited > DataService.SLOW_LOAD_HINT then
			hinted = true
			setAttr(player, "VP_LoadState", "waiting")
		end
		if RunService:IsStudio() and waited > DataService.LOAD_TIMEOUT then
			settled = true
			warn(
				"[DataService] loading the save timed out in Studio; using an offline test profile"
			)
			return offlineSession(key), "offline"
		end
		task.wait(0.25)
	end
	return result, "store"
end

-- Decides where profiles live (see header). May yield up to ACCESS_PROBE_TIMEOUT in Studio.
local function chooseMode()
	if not RunService:IsStudio() then
		return "store", ProfileStore.New(DataService.STORE_NAME, template)
	end
	if game.PlaceId == 0 then
		print("[DataService] unpublished place: offline test profiles (progress is not saved)")
		return "offline", nil
	end
	local started = os.clock()
	while
		ProfileStore.DataStoreState == "NotReady"
		and os.clock() - started < DataService.ACCESS_PROBE_TIMEOUT
	do
		task.wait(0.2)
	end
	if ProfileStore.DataStoreState == "Access" then
		return "store", ProfileStore.New(DataService.STUDIO_STORE_NAME, template)
	end
	print(
		"[DataService] no DataStore access ("
			.. tostring(ProfileStore.DataStoreState)
			.. "): offline test profiles (progress is not saved)"
	)
	return "offline", nil
end

-- ---------------------------------------------------------------- players
local function onPlayerAdded(player: Player)
	if profiles[player] or loading[player] then
		return -- already loading/loaded (PlayerAdded + GetPlayers can both deliver a player)
	end
	loading[player] = true
	setAttr(player, "VP_LoadState", "loading")
	local key = "p_" .. player.UserId
	local profile, mode
	if DataService.Mode == "offline" then
		profile, mode = offlineSession(key), "offline"
	else
		profile, mode = storeSession(player, key)
	end
	loading[player] = nil
	if not profile then
		setAttr(player, "VP_LoadState", "failed")
		player:Kick("Could not load your save. Please rejoin.")
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Your save was opened elsewhere. Please rejoin.")
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	migrate(profile.Data)
	profiles[player] = profile
	setAttr(player, "VP_SaveMode", mode)
	if profile.Data.stats.firstJoin == 0 then
		profile.Data.stats.firstJoin = os.time()
	end
	hydrating[player] = true
	for _, hook in loadHooks do
		local okHook, errHook = pcall(hook.fn, player, profile.Data)
		if not okHook then
			warn("[DataService] load hook " .. hook.name .. " failed: " .. tostring(errHook))
		end
	end
	hydrating[player] = nil
	loaded:Fire(player, profile.Data)
	local ok, err = pcall(DataService.Replicate, player)
	if not ok then
		warn("[DataService] initial replication failed: " .. tostring(err))
		setAttr(player, "VP_LoadState", "failed")
		return
	end
	setAttr(player, "VP_LoadState", "ready")
	-- Deferred PlayerLoaded handlers run after this thread: resend once they are done so nothing
	-- they changed is lost even if a handler forgets to replicate.
	task.defer(function()
		if profiles[player] == profile then
			pcall(DataService.Replicate, player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile.Data.stats.lastSeen = os.time()
		unloading:Fire(player, profile.Data)
		profile:EndSession()
		profiles[player] = nil
	end
end

function DataService.Get(player: Player)
	local profile = profiles[player]
	return profile and profile.Data or nil
end

function DataService.IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

local function publicSnapshot(data)
	local snapshot = {}
	for _, key in DataTemplate.PUBLIC_KEYS do
		snapshot[key] = data[key]
	end
	return snapshot
end

-- Sends the whole public profile (used on load and after large changes).
function DataService.Replicate(player: Player)
	local data = DataService.Get(player)
	if not data or hydrating[player] then
		return
	end
	Remotes.fire("ProfileDelta", player, publicSnapshot(data))
end

-- Sends only the listed top-level keys.
function DataService.ReplicateKeys(player: Player, keys: { string })
	local data = DataService.Get(player)
	if not data or hydrating[player] then
		return
	end
	local delta = {}
	for _, key in keys do
		delta[key] = data[key]
	end
	Remotes.fire("ProfileDelta", player, delta)
end

-- ---------------------------------------------------------------- lifecycle
function DataService.Start()
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Remotes.handle("GetProfile", function(player)
		local data = DataService.Get(player)
		if not data then
			return false, "Loading"
		end
		return true, nil, publicSnapshot(data)
	end)
	Remotes.handle("SetSetting", function(player, key, value)
		local data = DataService.Get(player)
		if not data then
			return false, "Loading"
		end
		if key == "battleSpeed" and Remotes.int(value, 1, 3) then
			data.settings.battleSpeed = value
		elseif
			(key == "autoSkip" or key == "music" or key == "sfx") and type(value) == "boolean"
		then
			data.settings[key] = value
		else
			return false, "Bad setting"
		end
		return true
	end)
end

-- Runs after every service's Start(): now it is safe to load players (all PlayerLoaded
-- listeners and load hooks are registered).
function DataService.Ready()
	local mode, s = chooseMode()
	DataService.Mode, store = mode, s
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService
