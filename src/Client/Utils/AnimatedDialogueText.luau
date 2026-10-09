-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Utils > AnimatedDialogueText (ModuleScript)
-- Texto letra por letra con entrada animada. Cada letra es un TextLabel propio posicionado a
-- mano: así cada una puede subir a su lugar sin mover el corte de línea final.
-- Lo usan los diálogos de NPC (DialogueController) y los anuncios (AdminBroadcastController):
-- el ritmo de escritura y cuándo suena la voz salen de acá, así los dos se sienten iguales.
local TextService = game:GetService("TextService")

export type Typing = {
	LetterDelay: number,
	-- Veces LetterDelay que dura la pausa tras . , ! ? ; :
	PunctuationPause: number,
	-- Con menos de ShortLetters letras se escribe más lento, hasta MaxSlowdown veces.
	ShortLetters: number,
	MaxSlowdown: number,
	-- Puntos suspensivos: cada punto espera DotDelay y suena con tono DotPitch.
	DotDelay: number,
	DotPitch: number,
	Entrance: number,
	Rise: number,
}

export type Align = "Left" | "Center"

type Glyph = {
	Char: string,
	Label: TextLabel,
	-- Segundo (desde el inicio de la línea) en que aparece.
	At: number,
	-- Tono con el que suena al aparecer; nil = no suena.
	Voice: number?,
	Width: number,
	X: number,
	Y: number,
	Line: number,
	-- false hasta que Layout le da posición: sin esto se veía en (0, 0), arriba a la izquierda.
	Placed: boolean,
}

local AnimatedDialogueText = {}
AnimatedDialogueText.__index = AnimatedDialogueText

-- Alto de línea respecto del tamaño de letra.
local LINE_HEIGHT = 1.28
-- Espacio extra entre letras (px): sin él, las del outline se tocan.
local LETTER_GAP = 0.7

-- Compartido entre instancias: el ancho de una letra no cambia con la fuente y el tamaño fijos.
local widthCache: { [string]: number } = {}

function AnimatedDialogueText.new(
	frame: GuiObject,
	template: TextLabel,
	typing: Typing,
	soundEvery: number,
	align: Align?
)
	return setmetatable({
		frame = frame,
		template = template,
		typing = typing,
		soundEvery = math.max(1, soundEvery),
		align = align or "Left",
		-- (tono) por cada letra que debe sonar; el que lo usa reproduce su propio sonido.
		OnSpeak = nil :: ((number) -> ())?,
		glyphs = {} :: { Glyph },
		time = 0,
		duration = 0,
		fontSize = template.TextSize,
		ready = false,
		-- Cambia en cada Set/Layout: una medición que vuelve tarde (es async) se descarta.
		revision = 0,
	}, AnimatedDialogueText)
end

local function setTransparency(label: TextLabel, value: number)
	label.TextTransparency = value
	local outline = label:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Transparency = value
	end
end

function AnimatedDialogueText:Clear()
	self.revision += 1
	self.ready = false
	for _, glyph in self.glyphs do
		glyph.Label:Destroy()
	end
	table.clear(self.glyphs)
end

local function isLetter(char: string): boolean
	return not char:match("^[%s%p]+$")
end

local function isEllipsis(chars: { string }, index: number): boolean
	local char = chars[index]
	return char == "…" or char == "." and (chars[index - 1] == "." or chars[index + 1] == ".")
end

-- AbsoluteSize ya viene multiplicado por los UIScale de arriba (ej. el pop de entrada del
-- anuncio): se divide para medir en px de diseño, que es lo que usan las letras.
local function unscaledWidth(frame: GuiObject): number
	local scale = 1
	local node: Instance? = frame
	while node and node:IsA("GuiObject") do
		for _, child in node:GetChildren() do
			if child:IsA("UIScale") and child.Scale > 0 then
				scale *= child.Scale
			end
		end
		node = node.Parent
	end
	return frame.AbsoluteSize.X / scale
end

-- Devuelve el alto del texto en px, como Layout.
function AnimatedDialogueText:Set(text: string): number?
	self:Clear()
	self.time = 0
	self.duration = 0
	local typing = self.typing
	local chars = {}
	local letters = 0
	for first, last in utf8.graphemes(text) do
		local char = text:sub(first, last)
		table.insert(chars, char)
		if isLetter(char) then
			letters += 1
		end
	end
	-- Pocas letras = más lento, como un personaje que duda.
	local slowdown = math.clamp(typing.ShortLetters / math.max(letters, 1), 1, typing.MaxSlowdown)
	-- La voz cuenta solo letras (no espacios ni signos): así suena parejo, una cada SoundEvery.
	local spoken = 0
	for index, char in chars do
		local voice: number? = nil
		local delay
		if isEllipsis(chars, index) then
			voice = typing.DotPitch
			delay = typing.DotDelay
		else
			if isLetter(char) then
				if spoken % self.soundEvery == 0 then
					voice = 1
				end
				spoken += 1
			end
			local isPunctuation = char:match("^[%.,!%?;:]$") ~= nil
			delay = typing.LetterDelay * slowdown * (if isPunctuation then typing.PunctuationPause else 1)
		end
		local label = self.template:Clone()
		label.Name = "Glyph"
		label.Text = char
		label.Visible = false
		label.Parent = self.frame
		table.insert(
			self.glyphs,
			{
				Char = char,
				Label = label,
				At = self.duration,
				Voice = voice,
				Width = 0,
				X = 0,
				Y = 0,
				Line = 0,
				Placed = false,
			}
		)
		self.duration += delay
	end
	return self:Layout()
end

local function measureChar(template: TextLabel, char: string, size: number): number?
	local key = ("%s:%d:%s"):format(tostring(template.FontFace), size, char)
	local cached = widthCache[key]
	if cached then
		return cached
	end
	local params = Instance.new("GetTextBoundsParams")
	params.Font = template.FontFace
	params.Text = char
	params.Size = size
	params.Width = 10000
	local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
	params:Destroy()
	if not ok then
		return nil
	end
	widthCache[key] = bounds.X
	return bounds.X
end

-- Corte por palabra: si la palabra entera no entra en lo que queda de línea, baja completa.
-- Devuelve el alto del texto en px, o nil si otra llamada la dejó vieja mientras medía.
function AnimatedDialogueText:Layout(): number?
	self.revision += 1
	local revision = self.revision
	self.ready = false
	for _, glyph in self.glyphs do
		glyph.Label.Visible = false
		glyph.Placed = false
	end

	local size = self.fontSize
	local width = math.max(1, unscaledWidth(self.frame))
	for _, glyph in self.glyphs do
		local measured = measureChar(self.template, glyph.Char, size)
		if self.revision ~= revision then
			return nil
		end
		-- Si la API web falla, una estimación evita que todo quede encimado.
		glyph.Width = (measured or size * 0.55) + LETTER_GAP
	end

	local line = size * LINE_HEIGHT
	local x, y = 0, 0
	for index, glyph in self.glyphs do
		glyph.Line = math.floor(y / line + 0.5)
		if glyph.Char == "\n" then
			glyph.X, glyph.Y = 0, y + line / 2
			x = 0
			y += line
			continue
		end
		local startsWord = glyph.Char ~= " " and (index == 1 or self.glyphs[index - 1].Char:match("%s") ~= nil)
		if startsWord then
			local word = 0
			for next = index, #self.glyphs do
				local other = self.glyphs[next]
				if other.Char:match("%s") then
					break
				end
				word += other.Width
			end
			if x > 0 and x + word > width then
				x = 0
				y += line
			end
		end
		-- Palabra más larga que la línea: se corta por letra.
		if x > 0 and x + glyph.Width > width then
			x = 0
			y += line
		end
		glyph.Line = math.floor(y / line + 0.5)
		if x == 0 and glyph.Char == " " then
			glyph.X, glyph.Y = 0, y + line / 2
		else
			glyph.X, glyph.Y = x + glyph.Width / 2, y + line / 2
			x += glyph.Width
		end
	end

	if self.align == "Center" then
		-- Ancho de cada línea sin el espacio final, y se corre cada una hasta el centro.
		local lineWidths: { [number]: number } = {}
		for _, glyph in self.glyphs do
			if glyph.Char ~= " " and glyph.Char ~= "\n" then
				lineWidths[glyph.Line] = math.max(lineWidths[glyph.Line] or 0, glyph.X + glyph.Width / 2)
			end
		end
		for _, glyph in self.glyphs do
			glyph.X += (width - (lineWidths[glyph.Line] or 0)) / 2
		end
	end

	-- Cada letra queda Visible y transparente en su punto de entrada; aparece solo por
	-- transparencia. Si se mostraba con Visible en el mismo frame en que recibía su posición,
	-- Roblox la dibujaba un frame en (0, 0), entre el nombre y el texto.
	for _, glyph in self.glyphs do
		local label = glyph.Label
		label.TextSize = size
		label.Size = UDim2.fromOffset(glyph.Width + 6, line)
		label.Position = UDim2.fromOffset(glyph.X, glyph.Y + self.typing.Rise)
		setTransparency(label, 1)
		label.Visible = true
		glyph.Placed = true
	end
	self.ready = true
	self:Render()
	return y + line
end

function AnimatedDialogueText:IsFinished(): boolean
	return self.time >= self.duration
end

function AnimatedDialogueText:Skip()
	self.time = self.duration + self.typing.Entrance
	self:Render()
end

function AnimatedDialogueText:Render()
	if not self.ready then
		return
	end
	local typing = self.typing
	local finished = self:IsFinished()
	for _, glyph in self.glyphs do
		local age = self.time - glyph.At
		if not glyph.Placed or age < 0 then
			continue
		end
		local progress = if finished then 1 else math.clamp(age / typing.Entrance, 0, 1)
		-- Cúbica: sube rápido y se asienta suave en su lugar, sin movimiento después.
		local settling = (1 - progress) ^ 3
		glyph.Label.Position = UDim2.fromOffset(glyph.X, glyph.Y + settling * typing.Rise)
		setTransparency(glyph.Label, 1 - math.min(1, progress * 4))
	end
end

-- Si en un mismo frame entran varias letras con voz, suena una sola vez.
function AnimatedDialogueText:Update(dt: number)
	if not self.ready then
		return
	end
	local before = self.time
	self.time += dt
	local pitch: number? = nil
	for _, glyph in self.glyphs do
		if glyph.Voice and glyph.At >= before and glyph.At < self.time then
			pitch = glyph.Voice
		end
	end
	if pitch and self.OnSpeak then
		self.OnSpeak(pitch)
	end
	self:Render()
end

function AnimatedDialogueText:Destroy()
	self:Clear()
end

return AnimatedDialogueText
