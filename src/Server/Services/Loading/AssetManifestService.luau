-- Ubicación en Studio: ServerScriptService > Services > Loading > AssetManifestService (ModuleScript)
-- Publica en ReplicatedStorage.ServerAssetManifest los asset IDs que solo ve el servidor.
local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local Assets = require(RS:WaitForChild("PreloadAssets"))
local Service = {}
function Service.Init()
	local found = {}
	local function add(id)
		found[id] = true
	end
	-- Workspace en el servidor incluye lo que todavía no se streameó al cliente.
	for _, root in { ServerStorage, workspace, Lighting, MaterialService } do
		Assets.forEachAssetId(root, add)
	end
	for _, id in Assets.collect() do
		add(id)
	end
	local function publish()
		local ids = {}
		for id in found do
			local kind = Assets.Kinds[id] or { Class = "ImageLabel", Property = "Image" }
			table.insert(ids, id .. "\t" .. kind.Class .. "\t" .. kind.Property)
		end
		table.sort(ids)
		local m = RS:FindFirstChild("ServerAssetManifest") or Instance.new("StringValue")
		m.Name = "ServerAssetManifest"
		m.Value = table.concat(ids, "\n")
		m.Parent = RS
	end
	publish()
	local scheduled = false
	local function added(o)
		local changed = false
		Assets.scanInstance(o, function(id)
			if not found[id] then
				found[id] = true
				changed = true
			end
		end)
		if changed and not scheduled then
			scheduled = true
			task.delay(0.5, function()
				scheduled = false
				publish()
			end)
		end
	end
	ServerStorage.DescendantAdded:Connect(added)
	workspace.DescendantAdded:Connect(added)
end
return Service
