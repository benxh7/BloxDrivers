-- Tiempos de la ENTRADA de las cards de la votación. Único lugar tuneable: lo lee el
-- cliente (VotingMapClient) para animar la caída, y MapVoteService para RETRASAR el
-- conteo justo esa duración — así el tiempo no baja mientras los mapas todavía entran
-- (mismo criterio que WaveTransitionConfig: un solo lugar, los dos lados derivan de acá).
local VotingMapConfig = {}

-- Cada card cae desde DropDistance px por encima de su lugar (Back Out = "boing"), una
-- tras otra cada DropStagger seg.
VotingMapConfig.DropDistance = 70
VotingMapConfig.DropDuration = 0.45
VotingMapConfig.DropStagger = 0.35

-- Colchón extra sobre la entrada (espera de layout + red): para que el cliente ya tenga
-- los 3 mapas en pantalla cuando llega el primer tick del server.
VotingMapConfig.EntranceBuffer = 0.5

-- SALIDA: "0s left" → sube a los perdedores, el ganador baja, crece, se queda un rato y
-- hace el boing (baja un poquito y sale disparado para arriba). Duraciones acá porque el
-- server espera celebrationDuration() antes de cerrar con el iris.
VotingMapConfig.ZeroHold = 0.5
VotingMapConfig.WinnerDelay = 0.25
VotingMapConfig.WinnerMoveDuration = 0.35
VotingMapConfig.WinnerGrowDuration = 0.5
VotingMapConfig.WinnerHold = 3 -- cuánto se queda agrandado en pantalla antes del boing
VotingMapConfig.WinnerExitDuration = 0.55

-- Cuánto tarda en aterrizar la última card (la que destraba el contador).
function VotingMapConfig.entranceDuration(count: number): number
	if count <= 1 then
		return VotingMapConfig.DropDuration
	end
	return (count - 1) * VotingMapConfig.DropStagger + VotingMapConfig.DropDuration
end

-- Desde que se cierra la votación hasta que el ganador termina de salir de pantalla.
function VotingMapConfig.celebrationDuration(): number
	return VotingMapConfig.ZeroHold
		+ VotingMapConfig.WinnerDelay
		+ VotingMapConfig.WinnerMoveDuration
		+ VotingMapConfig.WinnerGrowDuration
		+ VotingMapConfig.WinnerHold
		+ VotingMapConfig.WinnerExitDuration
end

return VotingMapConfig
