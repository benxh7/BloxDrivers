-- Ubicación en Studio: ServerScriptService > Services > Loading > AssetManifestService (ModuleScript)
-- ServerStorage no replica: el servidor publica sus asset IDs para que la carga los precargue.
-- No cubre el terreno: PreloadAsync no puede bajarlo.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PreloadAssets = require(ReplicatedStorage:WaitForChild("PreloadAssets"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local AssetManifestService = {}

-- El nombre lo espera LoadingScript: no cambiarlo sin cambiarlo allá.
local MANIFEST_NAME = "ServerAssetManifest"
local SEPARATOR = "\n"

-- Código sin assets: recorrerlo es tiempo de arranque perdido.
local SKIP_CHILDREN = { EasyProfileStore = true }

function AssetManifestService.Init()
	local seen: { [string]: true } = {}
	local ids: { string } = {}

	local scanned = 0
	for _, child in ServerStorage:GetChildren() do
		if SKIP_CHILDREN[child.Name] then
			continue
		end
		scanned += 1
		PreloadAssets.forEachAssetId(child, function(id)
			if seen[id] then
				return
			end
			seen[id] = true
			table.insert(ids, id)
		end)
	end

	-- Un solo StringValue (no una Instance por ID), lleno antes de parentarlo y creado
	-- aunque quede vacío: el cliente distingue "no llegó" de "no hay nada".
	local manifest = Instance.new("StringValue")
	manifest.Name = MANIFEST_NAME
	manifest.Value = table.concat(ids, SEPARATOR)
	manifest.Parent = ReplicatedStorage

	DebugConfig.print(
		("[AssetManifestService] %d assets de %d carpetas de ServerStorage listos para precargar"):format(#ids, scanned)
	)
end

return AssetManifestService
