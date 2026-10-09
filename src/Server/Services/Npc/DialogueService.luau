-- Ubicación en Studio: ServerScriptService > Services > Npc > DialogueService (ModuleScript)
-- Pone el ProximityPrompt "Talk" en cada NPC con DialogueConfig. Solo eso: el diálogo es
-- presentación del cliente, no da premios ni dispara acciones de juego.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DialogueConfig = require(ReplicatedStorage:WaitForChild("DialogueConfig"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local DialogueService = {}

-- Atributo que marca el prompt como propio: así no se borra uno puesto a mano en Studio.
local OWN_ATTRIBUTE = "NPCDialogue"
local ROOT_WAIT_TIMEOUT = 10

local watched: { [Model]: boolean } = {}

local function attachPrompt(model: Instance)
	if not model:IsA("Model") or watched[model] then
		return
	end
	watched[model] = true
	task.spawn(function()
		local root = model:FindFirstChild("HumanoidRootPart") or model:WaitForChild("Head", ROOT_WAIT_TIMEOUT)
		if not (root and root:IsA("BasePart") and model:IsDescendantOf(Workspace)) then
			watched[model] = nil
			DebugConfig.warn(("[Dialogue] %s no tiene de dónde colgar el prompt"):format(model.Name))
			return
		end
		local prompt = root:FindFirstChild(DialogueConfig.PromptName) :: ProximityPrompt?
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Name = DialogueConfig.PromptName
		end
		local p = prompt :: ProximityPrompt
		p.ActionText = DialogueConfig.Prompt.ActionText
		p.ObjectText = ""
		p.KeyboardKeyCode = Enum.KeyCode.E
		p.GamepadKeyCode = Enum.KeyCode.ButtonX
		p.HoldDuration = 0
		p.MaxActivationDistance = DialogueConfig.Prompt.Distance
		p.RequiresLineOfSight = false
		p:SetAttribute(OWN_ATTRIBUTE, true)
		p.Parent = root
		DebugConfig.print(("[Dialogue] Prompt on %s"):format(model.Name))
	end)
end

local function detachPrompt(model: Instance)
	watched[model :: Model] = nil
	local prompt = model:FindFirstChild(DialogueConfig.PromptName, true)
	if prompt and prompt:GetAttribute(OWN_ATTRIBUTE) then
		prompt:Destroy()
	end
end

-- Tener el ModuleScript alcanza: el tag se pone solo, no hace falta Tag Editor.
local function onDescendantAdded(item: Instance)
	if item:IsA("ModuleScript") and item.Name == DialogueConfig.ConfigName then
		local model = item.Parent
		if model and model:IsA("Model") then
			CollectionService:AddTag(model, DialogueConfig.Tag)
		end
	end
end

local function onDescendantRemoving(item: Instance)
	if item:IsA("ModuleScript") and item.Name == DialogueConfig.ConfigName then
		local model = item.Parent
		if model and model:IsA("Model") then
			CollectionService:RemoveTag(model, DialogueConfig.Tag)
		end
	end
end

function DialogueService.Init()
	CollectionService:GetInstanceAddedSignal(DialogueConfig.Tag):Connect(attachPrompt)
	CollectionService:GetInstanceRemovedSignal(DialogueConfig.Tag):Connect(detachPrompt)
	for _, model in CollectionService:GetTagged(DialogueConfig.Tag) do
		attachPrompt(model)
	end
	for _, item in Workspace:GetDescendants() do
		onDescendantAdded(item)
	end
	Workspace.DescendantAdded:Connect(onDescendantAdded)
	Workspace.DescendantRemoving:Connect(onDescendantRemoving)
end

return DialogueService
