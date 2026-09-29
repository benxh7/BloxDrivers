local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService.Services

-- Requerir el módulo es lo que activa sus RemoteEvents (todo su código corre en
-- el top level). NPCAnimations/NPCBillboard no hace falta requerirlos: son
-- `.server.luau`, así que Roblox ya los corre solos como Script.
require(Services.MapVote.MapVoteService)
