--!nonstrict
-- Server bootstrap with failure isolation and status reporting (used by Main.server.luau and the
-- Lune smoke tests, so both boot exactly the same way).
--
-- Why: a single throwing module used to abort the whole server script. Remote handlers were then
-- never registered, so clients waited forever on "Loading your pets...". Now every step (remotes,
-- world, each service require, Start, Ready) runs under xpcall and the server keeps going.
--
-- Visibility (the tester does not need the Output window):
--   ReplicatedStorage attributes  VP_ServerState  "booting" | "ready" | "degraded"
--                                 VP_BootStage    step currently running
--                                 VP_BootErrors   newline-separated problems (truncated)
--   DevLog remote                 server warnings/errors pushed to developer clients
--                                 (Studio, or the place owner in live servers)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")

local Boot = {}

-- Require / Start / Ready order. DataService first: other services subscribe to its signals.
Boot.SERVICES = {
	"DataService",
	"EconomyService",
	"PetService",
	"MonetizationService",
	"AnnouncementService",
	"QuestService",
	"PrestigeService",
	"BattleService",
	"StageService",
	"HatchService",
	"ExpeditionService",
	"CampService",
	"ArenaService",
}

local MAX_ATTR_CHARS = 1500
local errors = {}
local state = "booting"

local function publish(stage)
	ReplicatedStorage:SetAttribute("VP_ServerState", state)
	if stage then
		ReplicatedStorage:SetAttribute("VP_BootStage", stage)
	end
	local text = table.concat(errors, "\n")
	if #text > MAX_ATTR_CHARS then
		text = string.sub(text, 1, MAX_ATTR_CHARS) .. " ..."
	end
	ReplicatedStorage:SetAttribute("VP_BootErrors", text)
end

local function traceback(err)
	return tostring(err) .. "\n" .. debug.traceback(nil, 2)
end

-- Records a failed step. The attribute gets the first line only; Output/DevLog get everything.
function Boot.fail(stage: string, err)
	local text = tostring(err)
	local firstLine = string.match(text, "^[^\n]*") or text
	table.insert(errors, stage .. ": " .. firstLine)
	warn("[Boot] " .. stage .. " failed: " .. text)
	publish(nil)
end

function Boot.step(stage: string, fn): boolean
	publish(stage)
	local ok, err = xpcall(fn, traceback)
	if not ok then
		Boot.fail(stage, err)
	end
	return ok
end

function Boot.errors()
	return table.clone(errors)
end

-- ---------------------------------------------------------------- dev log forwarding
local LOG_MAX = 40 -- history kept for developers who join later
local RATE_WINDOW, RATE_MAX = 10, 30
local history = {}
local devs = {} -- [player] = true
local rate = { windowStart = 0, count = 0 }
local remotes = nil

local function isDev(player): boolean
	if RunService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function forward(kind: string, text: string)
	local now = os.clock()
	if now - rate.windowStart > RATE_WINDOW then
		rate.windowStart, rate.count = now, 0
	end
	rate.count += 1
	if rate.count > RATE_MAX then
		return
	end
	local last = history[#history]
	if last and last.text == text then
		last.count += 1
	else
		table.insert(
			history,
			{ t = os.time(), kind = kind, text = string.sub(text, 1, 600), count = 1 }
		)
		if #history > LOG_MAX then
			table.remove(history, 1)
		end
	end
	if remotes then
		local entry = history[#history]
		for player in devs do
			pcall(remotes.fire, "DevLog", player, { entry })
		end
	end
end

function Boot.startDevLog(Remotes)
	remotes = Remotes
	LogService.MessageOut:Connect(function(message, messageType)
		if messageType == Enum.MessageType.MessageError then
			forward("error", message)
		elseif messageType == Enum.MessageType.MessageWarning then
			forward("warn", message)
		end
	end)
	local function onPlayer(player)
		if isDev(player) then
			devs[player] = true
			pcall(player.SetAttribute, player, "VP_Dev", true)
			if #history > 0 then
				pcall(remotes.fire, "DevLog", player, history)
			end
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		devs[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
end

-- ---------------------------------------------------------------- boot
-- opts.root: the Server folder (default script.Parent); opts.world = false skips WorldBuilder.
function Boot.run(opts)
	opts = opts or {}
	local Server = opts.root or script.Parent
	state = "booting"
	publish("start")

	local Registry = require(Server.Registry)
	local Remotes = nil
	if Boot.step("Remotes", function()
		Remotes = require(Server.Network.Remotes)
	end) then
		Boot.step("DevLog", function()
			Boot.startDevLog(Remotes)
		end)
	end
	if opts.world ~= false then
		Boot.step("World", function()
			require(Server.World.WorldBuilder).Build()
		end)
	end
	for _, name in Boot.SERVICES do
		Boot.step(name, function()
			require(Server.Services[name])
		end)
	end
	publish("Start")
	Registry.startAll(Boot.fail)
	publish("Ready")
	Registry.readyAll(Boot.fail)
	if Remotes then
		local missing = Remotes.fillMissing()
		if #missing > 0 then
			Boot.fail("Remotes", "no handler for " .. table.concat(missing, ", "))
		end
	end

	state = #errors == 0 and "ready" or "degraded"
	publish("done")
	print(
		string.format(
			"[VoxelPets] server %s (%d problem%s)",
			state,
			#errors,
			#errors == 1 and "" or "s"
		)
	)
	return state, Boot.errors()
end

return Boot
