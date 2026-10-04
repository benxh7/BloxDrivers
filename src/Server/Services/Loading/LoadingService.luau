-- Ubicación en Studio: ServerScriptService > Services > Loading > LoadingService (ModuleScript)
-- El cliente avisa con SetLoadingComplete al apretar PLAY/SKIP; queda en el atributo LOADED_ATTRIBUTE.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local LoadingService = {}

-- Puesto por el servidor: replica a todos y un exploit no puede ponérselo a otro jugador.
local LOADED_ATTRIBUTE = "LoadingComplete"
local COOLDOWN = 1

function LoadingService.IsLoaded(player: Player): boolean
	return player:GetAttribute(LOADED_ATTRIBUTE) == true
end

function LoadingService.Init()
	Remotes.onServerEvent("SetLoadingComplete", function(player: Player)
		player:SetAttribute(LOADED_ATTRIBUTE, true)
	end, COOLDOWN)
end

return LoadingService
