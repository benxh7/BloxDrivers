-- Prendé/apagá acá los prints/warns/mensajes de debug de todo el proyecto
-- (servidor y cliente comparten este módulo).
local RunService = game:GetService("RunService")

local DebugConfig = {}

DebugConfig.ENABLED = true

-- Cheats de debug (botones del topbar, etc.). Solo en Studio,
-- NUNCA en el juego publicado, aunque ENABLED quede en true por descuido.
-- Gatea el cliente (no se crean los botones) Y el servidor (los handlers de los
-- remotes) — sin el gate del servidor, un exploiter podría dispararlos igual: el
-- remote existe aunque el botón no esté en su pantalla.
DebugConfig.CHEATS_ENABLED = RunService:IsStudio()

-- Subir a mano en cada release, para saber qué versión corre el juego.
DebugConfig.VERSION = "0.1.0"
DebugConfig.AUTHOR = ""

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

-- Corre una vez por VM: el banner aparece en la consola de cada cliente y
-- del servidor por separado.
if DebugConfig.ENABLED then
	print("")
	print(" BloxDrivers")
	print(" Version: " .. DebugConfig.VERSION)
	print("")
end

return DebugConfig
