-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > TopbarController (ModuleScript)
-- Comportamiento de los íconos del topbar (el arte y el orden van en TopbarConfig).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Icon = require(ReplicatedStorage:WaitForChild("TopbarPlus"):WaitForChild("Icon"))
local TopbarConfig = require(ReplicatedStorage:WaitForChild("TopbarConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local UIManager = require(script.Parent:WaitForChild("UIManager"))
local VotingMapController = require(script.Parent:WaitForChild("VotingMapController"))

local TopbarController = {}

-- Ícono (clave de TopbarConfig.Icons) -> ventana de UIManager.
local WINDOW_ICONS: { [string]: string } = {}

-- Un re-run del controller en Studio no debe duplicar el ícono.
local function newIcon(name: string)
	local existing = Icon.getIcon(name)
	if existing then
		existing:destroy()
	end
	return Icon.new():setName(name)
end

local function createWindowIcon(iconName: string, windowName: string)
	local icon = TopbarConfig.apply(newIcon(iconName), iconName)
	-- Refleja el estado de la ventana, la abra quien la abra (HUD, NPC, etc.).
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

	-- Solo Studio. El servidor rechaza DebugMapVote con el mismo gate si igual se dispara.
	if DebugConfig.CHEATS_ENABLED then
		createDebugIcons()
	end
end

return TopbarController
