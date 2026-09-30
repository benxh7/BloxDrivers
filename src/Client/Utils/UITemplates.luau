-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Utils > UITemplates (ModuleScript)
-- Acceso a las plantillas de ReplicatedStorage > UITemplates (se arman a mano en Studio).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local UITemplates = {}

local FOLDER_NAME = "UITemplates"
local WAIT_TIMEOUT = 10

local folder: Instance? = nil

local function getFolder(): Instance?
	if not folder then
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
		if not folder then
			DebugConfig.warn(("[UITemplates] Falta la carpeta ReplicatedStorage.%s (creala en Studio)"):format(FOLDER_NAME))
		end
	end
	return folder
end

-- La original: no modificarla, usar UITemplates.clone.
function UITemplates.get(name: string): GuiObject?
	local templates = getFolder()
	if not templates then
		return nil
	end
	local template = templates:WaitForChild(name, WAIT_TIMEOUT)
	if not (template and template:IsA("GuiObject")) then
		DebugConfig.warn(("[UITemplates] No existe la plantilla '%s' en ReplicatedStorage.%s"):format(name, FOLDER_NAME))
		return nil
	end
	return template
end

function UITemplates.clone(name: string): GuiObject?
	local template = UITemplates.get(name)
	if not template then
		return nil
	end
	local copy = template:Clone()
	copy.Visible = true
	return copy
end

return UITemplates
