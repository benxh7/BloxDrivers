-- Ubicación en Studio: ReplicatedStorage > DialogueConfig (ModuleScript)
-- Diálogos de NPC: cualquier Model con un ModuleScript hijo "DialogueConfig" que devuelva
-- { Name, Lines, IdleAnimation?, Enabled? }. Acá van los ajustes globales.
local DialogueConfig = {}

-- Nombre del ModuleScript hijo de cada NPC (no confundir con este módulo).
DialogueConfig.ConfigName = "DialogueConfig"
DialogueConfig.Tag = "DialogueNPC"
DialogueConfig.PromptName = "DialoguePrompt"

-- Nombre de la ventana en UIManager.
DialogueConfig.WindowName = "Dialogue"

DialogueConfig.Prompt = {
	ActionText = "Talk",
	-- Studs a los que aparece la "E".
	Distance = 10,
}

-- Studs a los que el diálogo se cierra solo si el jugador se aleja.
DialogueConfig.CloseDistance = 24

-- Ritmo de escritura, el mismo que los anuncios (AdminConfig.Typing). Tiempos en segundos.
DialogueConfig.Typing = {
	LetterDelay = 0.04,
	-- Veces LetterDelay que dura la pausa tras . , ! ? ; :
	PunctuationPause = 5,
	-- Líneas con menos de ShortLetters letras se escriben más lento, hasta MaxSlowdown veces.
	ShortLetters = 20,
	MaxSlowdown = 3,
	-- Puntos suspensivos ("..." o "…"): cada punto suena, con esta pausa y este tono. Acá van a
	-- la velocidad de una letra (sin la pausa larga de los anuncios, que usan 0.3).
	DotDelay = 0.04,
	DotPitch = 0.85,
	-- Entrada de cada letra: sube desde Rise px más abajo hasta su lugar en Entrance segundos.
	Entrance = 0.24,
	Rise = 10,
}

DialogueConfig.Voice = {
	Sound = "rbxassetid://90579231801746",
	Volume = 0.5,
	Pitch = 1.2,
	-- Variación aleatoria del tono por sonido (0.05 = ±5%).
	PitchVariation = 0.05,
	-- Suena cada N letras: 1 = en todas, 2 = más suave.
	SoundEvery = 2,
}

-- Retrato 3D del NPC (ViewportFrame). FramingScale < 1 acerca la cámara.
DialogueConfig.Portrait = {
	-- "" = usa la IdleAnimation del NPCConfig del NPC, si tiene.
	IdleAnimation = "",
	-- Sin animación: balanceo leve de brazos y cabeza por código.
	ProceduralIdle = false,
	FieldOfView = 35,
	-- Giro del NPC en el retrato: 0 = de frente a la cámara; negativo = mira hacia la izquierda
	-- de la pantalla, positivo = hacia la derecha (el texto).
	YawDegrees = 20,
	-- 1 = el NPC entero justo en el frame; más = más margen; menos de 1 corta las piernas.
	FramingScale = 1.08,
	-- Fracción del alto del NPC por encima del centro a la que apunta la cámara.
	VerticalFocus = 0.26,
	FadeIn = 0.25,
}

export type Entry = {
	Enabled: boolean?,
	Name: string?,
	IdleAnimation: string?,
	Lines: { string },
}

-- Un Config roto o sin líneas deja a ESE NPC sin diálogo, sin tumbar al resto.
function DialogueConfig.get(model: Model): Entry?
	local module = model:FindFirstChild(DialogueConfig.ConfigName)
	if not (module and module:IsA("ModuleScript")) then
		return nil
	end
	local ok, entry = pcall(require, module)
	if not ok or type(entry) ~= "table" or entry.Enabled == false then
		return nil
	end
	if type(entry.Lines) ~= "table" or #entry.Lines == 0 then
		return nil
	end
	for _, line in entry.Lines do
		if type(line) ~= "string" then
			return nil
		end
	end
	return entry
end

return DialogueConfig
