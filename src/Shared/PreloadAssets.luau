local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Un barrido de Instances nunca puede ver un `rbxassetid://` escrito DENTRO de un
-- ModuleScript, y esas cosas se crean en runtime: sin esto se ven cargar en vivo.
-- Se caminan las tablas enteras, así sumar una skin o un ícono no toca este archivo.
local PreloadAssets = {}

-- Todo en pcall: esto alimenta la PANTALLA DE CARGA, así que un catálogo renombrado
-- tiene que costar un asset sin precargar, nunca romper el arranque.
-- Traído de UBG recortado a los catálogos que existen en BloxDrivers — sumá acá
-- cada config/catálogo nuevo que tenga assets (imágenes, sonidos, animaciones).
local SOURCES: { { any } } = {
	{ ReplicatedStorage, "TopbarConfig" }, -- íconos del topbar (se crean en runtime)
	{ ReplicatedStorage, "UIHelpers" }, -- sonido de click de los botones
	{ ReplicatedStorage, "WaveTransitionConfig" }, -- sonido de la ola de cierre del menú
}

-- Los catálogos son tablas de tablas: el tope corta cualquier estructura rara.
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

-- No deduplica: eso lo hace quien llama, que ya tiene su propio set.
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

-- Van aparte porque `PreloadAsync` reporta OK sobre una animación sin bajar nada:
-- las carga de verdad AnimationPreloader, con LoadAnimation.
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
