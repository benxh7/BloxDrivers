local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PreloadAssets = require(ReplicatedStorage.PreloadAssets)
local DebugConfig = require(ReplicatedStorage.DebugConfig)

-- Publica los asset IDs de TODO ServerStorage para que la pantalla de carga los
-- precargue AL ENTRAR, y no en pleno juego.
--
-- El problema que resuelve: ServerStorage no se replica, así que el cliente no puede
-- ver ni precargar lo que vive ahí (mapas, modelos). El servidor SÍ lo ve, arma la
-- lista acá y la deja en ReplicatedStorage.
--
-- Se barre ServerStorage ENTERO a propósito: lo que sumes ahí queda cubierto sin
-- tocar este archivo ni la pantalla de carga.
--
-- Viaja como UN StringValue con los IDs separados por saltos de línea: una Instance
-- por ID serían cientos de objetos replicados para nada.
--
-- OJO: esto NO cubre el TERRENO. `PreloadAsync` no puede bajar terreno.

local MANIFEST_NAME = "ServerAssetManifest"
local SEPARATOR = "\n"

-- Código vendorizado, sin un solo asset adentro: recorrerlo es tiempo de arranque
-- tirado a la basura.
local SKIP_CHILDREN = { EasyProfileStore = true }

-- Se crea SIEMPRE, aunque quede vacío: así el cliente distingue "todavía no llegó"
-- de "no hay nada que precargar" en vez de esperar de gusto.
local manifest = Instance.new("StringValue")
manifest.Name = MANIFEST_NAME
manifest.Value = ""
manifest.Parent = ReplicatedStorage

-- Sin yields entre crear el StringValue y llenarlo: un cliente no puede llegar a
-- leerlo a medio armar.
local seen: { [string]: true } = {}
local ids: { string } = {}

local scanned = 0
for _, child in ServerStorage:GetChildren() do
	if SKIP_CHILDREN[child.Name] then continue end
	scanned += 1
	PreloadAssets.forEachAssetId(child, function(id)
		if seen[id] then return end
		seen[id] = true
		table.insert(ids, id)
	end)
end

manifest.Value = table.concat(ids, SEPARATOR)

DebugConfig.print(("[ServerAssetManifest] %d assets de %d carpetas de ServerStorage listos para precargar")
	:format(#ids, scanned))
