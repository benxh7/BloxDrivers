-- Ubicación en Studio: ReplicatedStorage > VotingMapConfig (ModuleScript)
-- Tiempos de la votación: el cliente anima con ellos y MapVoteService retrasa el conteo
-- lo mismo, así el tiempo no baja mientras los mapas todavía entran.
local VotingMapConfig = {}

-- Cada card cae desde DropDistance (en altos de card, no px) y entra una cada
-- DropStagger segundos.
VotingMapConfig.DropDistance = 0.6
VotingMapConfig.DropDuration = 0.45
VotingMapConfig.DropStagger = 0.35

-- Colchón por layout y red: los mapas ya están en pantalla al primer tick del server.
VotingMapConfig.EntranceBuffer = 0.5

-- Salida del ganador. El server espera celebrationDuration() antes de cerrar con el iris.
VotingMapConfig.ZeroHold = 0.5
VotingMapConfig.WinnerDelay = 0.25
VotingMapConfig.WinnerMoveDuration = 0.35
VotingMapConfig.WinnerGrowDuration = 0.5
-- Segundos que el ganador queda agrandado antes de salir.
VotingMapConfig.WinnerHold = 3
VotingMapConfig.WinnerExitDuration = 0.55

function VotingMapConfig.entranceDuration(count: number): number
	if count <= 1 then
		return VotingMapConfig.DropDuration
	end
	return (count - 1) * VotingMapConfig.DropStagger + VotingMapConfig.DropDuration
end

function VotingMapConfig.celebrationDuration(): number
	return VotingMapConfig.ZeroHold
		+ VotingMapConfig.WinnerDelay
		+ VotingMapConfig.WinnerMoveDuration
		+ VotingMapConfig.WinnerGrowDuration
		+ VotingMapConfig.WinnerHold
		+ VotingMapConfig.WinnerExitDuration
end

return VotingMapConfig
