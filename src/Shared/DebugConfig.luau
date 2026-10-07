-- Ubicación en Studio: ReplicatedStorage > DebugConfig (ModuleScript)
-- Interruptor de todos los prints/warns del proyecto (servidor y cliente).
local RunService = game:GetService("RunService")

local DebugConfig = {}

DebugConfig.ENABLED = true

-- Gatea los cheats en el cliente Y en los handlers del servidor: el remote existe en
-- producción aunque el botón no, y un exploiter podría dispararlo igual.
DebugConfig.CHEATS_ENABLED = RunService:IsStudio()

-- Subir a mano en cada release.
DebugConfig.VERSION = "0.1.0"
DebugConfig.AUTHOR = "iHazeHD"

function DebugConfig.print(...: any)
	if DebugConfig.ENABLED then
		print(...)
	end
end

function DebugConfig.warn(...: any)
	if DebugConfig.ENABLED then
		warn(...)
	end
end

-- Corre una vez por VM: sale en la consola de cada cliente y del servidor.
if DebugConfig.ENABLED then
	print("")
	print(" BloxDrivers")
	print(" Version: " .. DebugConfig.VERSION)
	print("")
end

return DebugConfig
