-- Ubicación en Studio: ReplicatedStorage > TopbarConfig (ModuleScript)
-- Arte, texto, orden y lado de cada ícono del topbar; el comportamiento va en TopbarController.
-- Campos: `align` "Left"/"Right", `order`, `name`, e `image`/`caption`/`label` opcionales.
local TopbarConfig = {}

TopbarConfig.Icons = {}

-- Arte por estado de las casillas de un dropdown tipo "Opciones".
TopbarConfig.ToggleImages = {
	Selected = "",
	Deselected = "",
}

function TopbarConfig.apply(icon, name: string)
	local cfg = TopbarConfig.Icons[name]
	if not cfg then
		warn("[TopbarConfig] Sin config para el ícono '" .. tostring(name) .. "'")
		return icon
	end

	if cfg.name then
		icon:setName(cfg.name)
	end
	if cfg.image then
		icon:setImage(cfg.image)
	end
	-- El tema de TopbarPlus ya vacía el texto en Deselected.
	if cfg.label then
		icon:setLabel(cfg.label, "Viewing")
		icon:setLabel(cfg.label, "Selected")
	end
	if cfg.caption then
		icon:setCaption(cfg.caption)
	end
	if cfg.align == "Right" then
		icon:setRight()
	end
	icon:setOrder(cfg.order)
	return icon
end

return TopbarConfig
