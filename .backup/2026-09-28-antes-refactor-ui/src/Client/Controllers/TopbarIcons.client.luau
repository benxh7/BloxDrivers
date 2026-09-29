local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Icon = require(ReplicatedStorage:WaitForChild("TopbarPlus"):WaitForChild("Icon"))
local GameRemotes = require(ReplicatedStorage.Remotes.GameRemotes)
local DebugConfig = require(ReplicatedStorage.DebugConfig)

-- Traído de UBG (era TopbarPlusIconCreator.client.luau, el menú "Opciones" con
-- AFK/Hitboxes/Contornos/Spectate + una decena de debugs de bomba/economía) y
-- reducido a lo ÚNICO que BloxDrivers usa hoy de ese archivo: el debug que
-- dispara una votación de mapa REAL contra el servidor. Todo lo demás dependía
-- de sistemas que no se portaron (SetAfk, PlayerSettings, CharacterOutlineController,
-- SpectateEngine, HitboxDebugController, y los remotes Debug* de bomba/shop/misiones/XP).
--
-- Distinto del ícono "Map Vote (Debug)" que ya crea VotingMapClient: ese simula
-- todo 100% local sin tocar el server; este llama a MapVoteService de verdad.

-- SOLO en Studio. En el juego publicado ni se crea, y el servidor rechaza el
-- remote con el mismo gate (DebugConfig.CHEATS_ENABLED) si igual se dispara.
if DebugConfig.CHEATS_ENABLED then
	-- Evita duplicar el ícono si el script se re-corre (play-testing en Studio).
	local existing = Icon.getIcon("MapVoteRealDebug")
	if existing then
		existing:destroy()
	end

	local mapVoteRow = Icon.new()
	mapVoteRow:setName("MapVoteRealDebug")
	mapVoteRow:setLabel("Debug: Map Vote (real)")
	mapVoteRow:oneClick(true)
	mapVoteRow.selected:Connect(function()
		GameRemotes.DebugMapVote:FireServer()
	end)
end
