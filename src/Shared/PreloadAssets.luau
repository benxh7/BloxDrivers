-- Ubicación en Studio: ReplicatedStorage > PreloadAssets (ModuleScript)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Un barrido de Instances no ve los `rbxassetid://` escritos dentro de un ModuleScript
-- (se crean en runtime): por eso se recorren las tablas de los catálogos.
local PreloadAssets = {}

-- Catálogos con assets a precargar: sumar acá cada config nuevo con imágenes o sonidos.
local SOURCES: { { any } } = {
	{ ReplicatedStorage, "TopbarConfig" },
	{ ReplicatedStorage, "WaveTransitionConfig" },
	-- Los sonidos de UI no: UIEffects los precarga solo.
}

local MAX_DEPTH = 6

local ASSET_PROPERTIES: { [string]: { string } } = {
	Decal = { "Texture" },
	Texture = { "Texture" },
	ImageLabel = { "Image" },
	ImageButton = { "Image" },
	MeshPart = { "MeshId", "TextureID" },
	SpecialMesh = { "MeshId", "TextureId" },
	Sound = { "SoundId" },
	Animation = { "AnimationId" },
	VideoFrame = { "Video" },
	ParticleEmitter = { "Texture" },
	Beam = { "Texture" },
	Trail = { "Texture" },
}

-- No deduplica: lo hace quien llama.
function PreloadAssets.forEachAssetId(root: Instance, callback: (string) -> ())
	local function scan(instance: Instance)
		local properties = ASSET_PROPERTIES[instance.ClassName]
		if not properties then return end
		for _, property in properties do
			local ok, id = pcall(function()
				return (instance :: any)[property]
			end)
			if ok and typeof(id) == "string" and id ~= "" and id ~= "rbxassetid://0" then
				callback(id)
			end
		end
	end

	scan(root)
	for _, descendant in root:GetDescendants() do
		scan(descendant)
	end
end

local function isAssetId(value: any): boolean
	if typeof(value) ~= "string" then return false end
	local digits = value:match("^rbxassetid://(%d+)$")
	return digits ~= nil and digits ~= "0"
end

local function resolve(path: { any }): any
	local current = path[1]
	for index = 2, #path do
		if typeof(current) ~= "Instance" then return nil end
		current = current:FindFirstChild(path[index])
		if not current then return nil end
	end
	return current
end

-- `seenTables` corta ciclos: una tabla que se referencia a sí misma colgaría el loop.
local function walk(value: any, out: { [string]: true }, seenTables: { [any]: true }, depth: number)
	if depth > MAX_DEPTH then return end
	if isAssetId(value) then
		out[value] = true
		return
	end
	if typeof(value) ~= "table" or seenTables[value] then return end

	seenTables[value] = true
	for key, child in value do
		walk(key, out, seenTables, depth + 1)
		walk(child, out, seenTables, depth + 1)
	end
end

function PreloadAssets.collect(): { string }
	local found: { [string]: true } = {}
	local seenTables: { [any]: true } = {}

	for _, path in SOURCES do
		local moduleScript = resolve(path)
		if moduleScript and moduleScript:IsA("ModuleScript") then
			-- pcall: un catálogo roto cuesta un asset sin precargar, no el arranque.
			local ok, catalog = pcall(require, moduleScript)
			if ok then
			walk(catalog, found, seenTables, 0)
			end
		end
	end

	local ids = {}
	for id in found do
		table.insert(ids, id)
	end
	return ids
end

-- Aparte: PreloadAsync da OK sobre una animación sin bajarla (las carga AnimationPreloader).
function PreloadAssets.collectAnimationIds(): { string }
	local found: { [string]: true } = {}
	local seenTables: { [any]: true } = {}

	local function scan(value: any, depth: number)
		if depth > MAX_DEPTH or typeof(value) ~= "table" or seenTables[value] then return end
		seenTables[value] = true
		for key, child in value do
			if key == "AnimationId" and isAssetId(child) then
				found[child] = true
			end
			scan(child, depth + 1)
		end
	end

	for _, path in SOURCES do
		local moduleScript = resolve(path)
		if moduleScript and moduleScript:IsA("ModuleScript") then
			local ok, catalog = pcall(require, moduleScript)
			if ok then
				scan(catalog, 0)
			end
		end
	end

	local ids = {}
	for id in found do
		table.insert(ids, id)
	end
	return ids
end

return PreloadAssets
