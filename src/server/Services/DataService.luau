--!nonstrict
-- Profile loading/saving via ProfileStore (session locked). Other services read/write
-- profile.Data directly through DataService.Get(player) and call Replicate() after changes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ProfileStore = require(script.Parent.Parent.Vendor.ProfileStore)
local Remotes = require(script.Parent.Parent.Network.Remotes)
local Registry = require(script.Parent.Parent.Registry)
local DataTemplate = require(ReplicatedStorage.Shared.DataTemplate)

local DataService = Registry.register("DataService", {})

-- Template = data fields only (strip helper keys).
local template = {}
for k, v in DataTemplate do
	if k ~= "PUBLIC_KEYS" and k ~= "MAX_TEAM_SLOTS" then
		template[k] = v
	end
end

local STORE_NAME = "PlayerData_v1"
local store = ProfileStore.New(STORE_NAME, template)
if RunService:IsStudio() then
	store = store.Mock -- no DataStore access in Studio unless API access enabled; keeps tests clean
end

local profiles = {} -- [player] = profile
local loaded = Instance.new("BindableEvent")
DataService.PlayerLoaded = loaded.Event -- (player, data)
local unloading = Instance.new("BindableEvent")
DataService.PlayerUnloading = unloading.Event -- (player, data)

local function migrate(data)
	-- schemaVersion 1: nothing yet. Add `if data.schemaVersion < 2 then ... end` steps here.
	data.schemaVersion = DataTemplate.schemaVersion
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync("p_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if not profile then
		player:Kick("Could not load your save. Please rejoin.")
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your save was opened elsewhere. Please rejoin.")
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	migrate(profile.Data)
	profiles[player] = profile
	local now = os.time()
	if profile.Data.stats.firstJoin == 0 then
		profile.Data.stats.firstJoin = now
	end
	loaded:Fire(player, profile.Data)
	DataService.Replicate(player)
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

-- Sends the whole public profile (used on load and after large changes).
function DataService.Replicate(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local snapshot = {}
	for _, key in DataTemplate.PUBLIC_KEYS do
		snapshot[key] = data[key]
	end
	Remotes.fire("ProfileDelta", player, snapshot)
end

-- Sends only the listed top-level keys.
function DataService.ReplicateKeys(player: Player, keys: { string })
	local data = DataService.Get(player)
	if not data then
		return
	end
	local delta = {}
	for _, key in keys do
		delta[key] = data[key]
	end
	Remotes.fire("ProfileDelta", player, delta)
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Remotes.handle("GetProfile", function(player)
		local data = DataService.Get(player)
		if not data then
			return false, "Loading"
		end
		local snapshot = {}
		for _, key in DataTemplate.PUBLIC_KEYS do
			snapshot[key] = data[key]
		end
		return true, nil, snapshot
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
	Remotes.handle("TutorialStep", function(player, step)
		local data = DataService.Get(player)
		local s = Remotes.int(step, 0, 50)
		if not data or not s then
			return false, "Bad step"
		end
		data.tutorialStep = math.max(data.tutorialStep, s)
		return true
	end)
end

return DataService
