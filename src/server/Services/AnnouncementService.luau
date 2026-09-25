--!nonstrict
-- Cross-server ticker for rare hatches / prestige via MessagingService (best effort).
local MessagingService = game:GetService("MessagingService")

local Registry = require(script.Parent.Parent.Registry)
local Remotes = require(script.Parent.Parent.Network.Remotes)

local AnnouncementService = Registry.register("AnnouncementService", {})

local TOPIC = "VP_Announce_v1"

function AnnouncementService.Broadcast(text: string, kind: string)
	Remotes.fireAll("Announcement", text, kind)
	task.spawn(function()
		pcall(
			MessagingService.PublishAsync,
			MessagingService,
			TOPIC,
			{ text = text, kind = kind, jobId = game.JobId }
		)
	end)
end

function AnnouncementService.Start()
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(message)
				local payload = message.Data
				if
					type(payload) == "table"
					and payload.jobId ~= game.JobId
					and type(payload.text) == "string"
				then
					Remotes.fireAll("Announcement", payload.text, payload.kind)
				end
			end)
		end)
		if not ok then
			warn("[Announcements] MessagingService unavailable: " .. tostring(err))
		end
	end)
end

return AnnouncementService
