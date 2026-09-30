-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > TopbarController (ModuleScript)
--
-- Íconos del topbar (TopbarPlus). La identidad de cada ícono (arte, texto, orden,
-- lado) vive en Shared/TopbarConfig; acá solo va el comportamiento.
--
-- Hoy solo hay íconos de DEBUG (solo Studio):
--   · "Map Vote (real)": dispara DebugMapVote y corre la votación REAL en el servidor.
--   · "Map Vote (mock)": simulación 100% local, sin tocar el servidor.
--
-- Para un ícono de producción que abre una ventana: sumá su entrada en
-- TopbarConfig.Icons y en WINDOW_ICONS (nombre del ícono -> ventana de UIManager).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Icon = require(ReplicatedStorage:WaitForChild("TopbarPlus"):WaitForChild("Icon"))
local TopbarConfig = require(ReplicatedStorage:WaitForChild("TopbarConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local UIManager = require(script.Parent:WaitForChild("UIManager"))
local VotingMapController = require(script.Parent:WaitForChild("VotingMapController"))

local TopbarController = {}

-- Ícono (clave de TopbarConfig.Icons) -> ventana de UIManager. Vacío por ahora.
local WINDOW_ICONS: { [string]: string } = {}

-- Evita duplicar un ícono si el controller se re-corre (play-testing en Studio).
local function newIcon(name: string)
	local existing = Icon.getIcon(name)
	if existing then
		existing:destroy()
	end
	return Icon.new():setName(name)
end

local function createWindowIcon(iconName: string, windowName: string)
	local icon = TopbarConfig.apply(newIcon(iconName), iconName)
	-- El ícono refleja el estado de la ventana, la abra quien la abra (HUD, NPC, etc.).
	icon.selected:Connect(function()
		UIManager.Open(windowName)
	end)
	icon.deselected:Connect(function()
		UIManager.Close(windowName)
	end)
	UIManager.OnOpened(windowName, function()
		icon:select()
	end)
	UIManager.OnClosed(windowName, function()
		icon:deselect()
	end)
end

local function createDebugIcons()
	local realVote = newIcon("MapVoteRealDebug")
	realVote:setLabel("Map Vote (real)")
	realVote:oneClick(true)
	realVote.selected:Connect(function()
		Remotes.event("DebugMapVote"):FireServer()
	end)

	local mockVote = newIcon("MapVoteMockDebug")
	mockVote:setLabel("Map Vote (mock)")
	mockVote:oneClick(true)
	mockVote.selected:Connect(VotingMapController.RunMockVote)
end

function TopbarController.Init()
	for iconName, windowName in WINDOW_ICONS do
		createWindowIcon(iconName, windowName)
	end

	-- SOLO en Studio. En el juego publicado ni se crean, y el servidor rechaza el remote
	-- con el mismo gate (DebugConfig.CHEATS_ENABLED) si igual se dispara.
	if DebugConfig.CHEATS_ENABLED then
		createDebugIcons()
	end
end

return TopbarController
