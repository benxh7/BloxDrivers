-- Ubicación en Studio: ReplicatedStorage > PreloadAssets (ModuleScript)
-- Descubre asset IDs en instancias y en los *Config (que deben ser solo datos: los requiere).
local RS = game:GetService("ReplicatedStorage")
local Assets = {}
Assets.Kinds = {}
local properties = {
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
	Sky = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SunTextureId", "MoonTextureId" },
	SurfaceAppearance = { "ColorMap", "MetalnessMap", "NormalMap", "RoughnessMap" },
	MaterialVariant = { "ColorMap", "MetalnessMap", "NormalMap", "RoughnessMap" },
	Shirt = { "ShirtTemplate" },
	Pants = { "PantsTemplate" },
	ShirtGraphic = { "Graphic" },
}
function Assets.normalize(id)
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local digits = id:match("^rbxassetid://(%d+)$") or id:match("[?&]id=(%d+)")
	if digits then
		return tonumber(digits) > 0 and "rbxassetid://" .. digits or nil
	end
	if id:match("^rbxasset://") or id:match("^rbxthumb://") or id:match("^https?://") then
		return id
	end
	return nil
end
function Assets.scanInstance(o, callback)
	for _, key in properties[o.ClassName] or {} do
		local ok, value = pcall(function()
			return o[key]
		end)
		if ok then
			local id = Assets.normalize(value)
			if id then
				Assets.Kinds[id] = { Class = o.ClassName, Property = key }
				callback(id)
			end
		end
	end
	for _, value in o:GetAttributes() do
		local id = Assets.normalize(value)
		if id then
			callback(id)
		end
	end
end
function Assets.forEachAssetId(root, callback)
	Assets.scanInstance(root, callback)
	for _, o in root:GetDescendants() do
		Assets.scanInstance(o, callback)
	end
end
local function walk(value, found, seen, hint)
	local id = Assets.normalize(value)
	if id then
		found[id] = true
		if not Assets.Kinds[id] then
			Assets.Kinds[id] = hint or { Class = "ImageLabel", Property = "Image" }
		end
		return
	end
	if type(value) ~= "table" or seen[value] then
		return
	end
	seen[value] = true
	for k, v in value do
		local nextHint = hint
		if type(k) == "string" then
			local key = k:lower()
			if key:find("sound") or key:find("music") then
				nextHint = { Class = "Sound", Property = "SoundId" }
			elseif key:find("animation") then
				nextHint = { Class = "Animation", Property = "AnimationId" }
			end
		end
		walk(k, found, seen, hint)
		walk(v, found, seen, nextHint)
	end
end
function Assets.collect(root)
	local found, seen = {}, {}
	for _, o in (root or RS):GetDescendants() do
		if
			o:IsA("ModuleScript")
			and (o.Name:match("Config$") or o:GetAttribute("PreloadConfig") == true)
			and o:GetAttribute("PreloadConfig") ~= false
		then
			local ok, data = pcall(require, o)
			if ok then
				walk(data, found, seen)
			else
				warn("[PreloadAssets] " .. o:GetFullName() .. ": " .. tostring(data))
			end
		end
	end
	local ids = {}
	for id in found do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end
return Assets
