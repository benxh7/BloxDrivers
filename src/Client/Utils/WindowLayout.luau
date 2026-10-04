-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Utils > WindowLayout (ModuleScript)
-- Tamaño de ventana y de su Header (Icon, CloseButton, Title.TextLimit) según la pantalla.
local WindowLayout = {}

-- Main a lo ancho de la pantalla con tope de 920x640, igual en Shop y Settings.
function WindowLayout.fitMain(screen: Vector2, main: GuiObject): (number, number)
	local width = math.min(920, screen.X * (if screen.X < 1000 then 0.86 else 0.65))
	local height = math.min(640, screen.Y * (if screen.Y < 450 then 0.9 else 0.84))
	main.Size = UDim2.fromOffset(math.floor(width), math.floor(height))
	main.Position = UDim2.fromScale(0.5, 0.53)
	return width, height
end

-- `maxHeader`/`maxTitle` en px: tope del alto del Header y del texto del título.
function WindowLayout.fitHeader(header: any, height: number, maxHeader: number, maxTitle: number): (number, number)
	local headerHeight = math.clamp(height * 0.15, 50, maxHeader)
	header.Size = UDim2.new(1, 0, 0, headerHeight)
	header.Icon.Size = UDim2.fromOffset(headerHeight * 1.48, headerHeight * 1.48)
	local closeSize = math.clamp(headerHeight * 0.8, 44, 68)
	header.CloseButton.Size = UDim2.fromOffset(closeSize, closeSize)
	header.Title.TextLimit.MaxTextSize = math.clamp(headerHeight * 0.58, 24, maxTitle)
	return headerHeight, closeSize
end

return WindowLayout
