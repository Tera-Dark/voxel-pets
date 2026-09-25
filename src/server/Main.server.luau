--!nonstrict
-- Server bootstrap. Order: remotes -> world -> services (registered on require, started together).
local ServerScriptService = game:GetService("ServerScriptService")

local Server = script.Parent
local Registry = require(Server.Registry)
require(Server.Network.Remotes)

require(Server.World.WorldBuilder).Build()

-- Requiring registers each service; Start() wires remotes/events once everything exists.
local Services = Server.Services
require(Services.DataService)
require(Services.EconomyService)
require(Services.PetService)
require(Services.MonetizationService)
require(Services.AnnouncementService)
require(Services.QuestService)
require(Services.PrestigeService)
require(Services.BattleService)
require(Services.StageService)
require(Services.HatchService)
require(Services.ExpeditionService)
require(Services.CampService)
require(Services.ArenaService)

Registry.startAll()
print("[VoxelPets] server ready (" .. ServerScriptService.Name .. ")")
