-- Ubicación en Studio: ReplicatedStorage > TopbarConfig (ModuleScript)
--
-- Identidad + layout de CADA ícono del topbar. TopbarController llama
-- `TopbarConfig.apply(icon, "Nombre")`: acá va lo que DEFINE al ícono (arte, texto,
-- orden, lado), el comportamiento queda en TopbarController.
--
-- Campos: `align` "Left"/"Right", `order` ascendente dentro de cada lado, `name`
-- (id interno + de-dup), e `image`/`caption`/`label` opcionales.
--
-- Traído de UBG sin íconos propios: sumá acá el primer ícono de BloxDrivers
-- (ej. `Garage = { align = "Left", order = 1, name = "Garage", image = "rbxassetid://...", caption = "Garage" }`).
local TopbarConfig = {}

TopbarConfig.Icons = {}

-- Casillas de un dropdown tipo "Opciones" (un arte por estado). Vacío hasta que
-- BloxDrivers tenga su propio menú de opciones — pegá tus IDs acá.
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
	-- Solo en Viewing y Selected: el tema de TopbarPlus ya deja el texto vacío en
	-- Deselected, no hay que limpiarlo a mano.
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
