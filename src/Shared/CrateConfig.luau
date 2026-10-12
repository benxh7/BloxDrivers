-- Ubicación en Studio: ReplicatedStorage > CrateConfig (ModuleScript)
-- Cajas (cases): precios, premios con su peso, rarezas, sonidos y ritmo de la ruleta.
-- El servidor sortea con estos mismos pesos: lo que muestra el panel de probabilidades es real.
local CrateConfig = {}

-- Billetera de prueba solo en Studio: el juego todavía no tiene Cash/Gems guardados.
-- Fuera de Studio las compras con moneda responden "todavía no disponible".
CrateConfig.StudioDemo = true
CrateConfig.DemoCash = 50000
CrateConfig.DemoGems = 1000
-- Cajas de cada tipo que recibe el jugador de prueba al entrar (solo Studio).
CrateConfig.DemoOwned = 4

-- Nombre de la ventana en UIManager y del ProximityPrompt de cada cofre del lobby.
CrateConfig.WindowName = "Crates"
CrateConfig.PromptName = "CratePrompt"

CrateConfig.Reel = {
	-- Distancia (px de diseño) entre el centro de una tarjeta y la siguiente.
	Step = 245,
	-- Segundos que tarda en frenar una tirada y el salto de SKIP hasta el premio.
	SpinSeconds = 7.2,
	SkipSeconds = 0.35,
	-- Tarjetas que pasan antes de la ganadora (más = gira más rápido al principio).
	CardsBeforeWinner = 42,
	-- Píxeles por segundo con los que se desliza la ruleta mientras no se tira.
	IdleSpeed = 120,
	-- Segundos que queda visible el premio antes de la próxima tirada o de volver al reposo.
	RevealSeconds = 2,
	-- Grados por segundo que gira el arcoíris de los botones LUCKY SPIN.
	LuckyRotationSpeed = 18,
}

-- Cofre del lobby: en reposo cerrado; se abre mientras se ve la ruleta (solo para quien la abrió).
CrateConfig.Chest = {
	-- Grados que se abre la tapa y segundos de apertura (con rebote) y de cierre.
	OpenAngle = 75,
	OpenSeconds = 0.55,
	CloseSeconds = 0.35,
	-- Veces que se multiplica el brillo de la luz interior al abrir.
	GlowBoost = 3,
	-- Chispas que salen de golpe al abrir.
	SparkBurst = 30,
}

-- Mensajes que aparecen bajo la ruleta ("Rolled Flame!"): segundos en pantalla y máximo apilados.
CrateConfig.Toast = {
	Duration = 2.2,
	MaxStacked = 3,
}

CrateConfig.Sounds = {
	-- Suena una vez por tarjeta que cruza las flechas; MinGap evita que se amontonen.
	Tick = { Id = "rbxassetid://139800881181209", Volume = 0.3, Speed = 1.65, MinGap = 0.065 },
	LidOpen = { Id = "rbxassetid://119461042040425", Volume = 0.5 },
	Purchase = { Id = "rbxassetid://134810204798705", Volume = 0.45 },
	Error = { Id = "rbxassetid://124387798635805", Volume = 0.45 },
	-- Premio: el sonido de la rareza ganadora (sin entrada = Default).
	Win = {
		Default = { Id = "rbxassetid://109742263473623", Volume = 0.5 },
		Legendary = { Id = "rbxassetid://4612374036", Volume = 0.55 },
		Mythic = { Id = "rbxassetid://128460880879263", Volume = 0.55 },
		Secret = { Id = "rbxassetid://128460880879263", Volume = 0.6 },
		Abyssal = { Id = "rbxassetid://128460880879263", Volume = 0.6 },
	},
}

-- Colores de los mensajes: degradado de arriba a abajo y borde.
CrateConfig.ToastThemes = {
	Win = { Colors = { Color3.fromRGB(210, 255, 45), Color3.fromRGB(65, 245, 0) }, Stroke = Color3.fromRGB(30, 90, 10) },
	Info = { Colors = { Color3.fromRGB(170, 250, 255), Color3.fromRGB(45, 200, 255) }, Stroke = Color3.fromRGB(15, 65, 120) },
	Error = { Colors = { Color3.fromRGB(255, 120, 130), Color3.fromRGB(235, 30, 60) }, Stroke = Color3.fromRGB(90, 10, 25) },
}

CrateConfig.RarityOrder = { "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Abyssal" }

-- Color = el de la tarjeta y del texto de probabilidad; Stroke = borde de ese texto.
CrateConfig.Rarities = {
	Uncommon = { Color = Color3.fromRGB(104, 255, 132), Stroke = Color3.new(0, 0, 0) },
	Rare = { Color = Color3.fromRGB(106, 203, 255), Stroke = Color3.new(0, 0, 0) },
	Epic = { Color = Color3.fromRGB(192, 117, 255), Stroke = Color3.new(0, 0, 0) },
	Legendary = { Color = Color3.fromRGB(255, 226, 90), Stroke = Color3.new(0, 0, 0) },
	Mythic = { Color = Color3.fromRGB(255, 124, 210), Stroke = Color3.new(0, 0, 0) },
	Secret = { Color = Color3.fromRGB(240, 255, 255), Stroke = Color3.new(0, 0, 0) },
	Abyssal = { Color = Color3.fromRGB(40, 45, 130), Stroke = Color3.fromRGB(150, 160, 255) },
}

-- LUCKY SPIN multiplica el peso de cada rareza: baja lo común y sube lo raro.
CrateConfig.LuckyMultipliers = {
	Uncommon = 0.25,
	Rare = 1,
	Epic = 2,
	Legendary = 3,
	Mythic = 4,
	Secret = 4,
	Abyssal = 4,
}

export type Reward = {
	Id: string,
	Name: string,
	Rarity: string,
	-- Peso relativo dentro de la caja (no hace falta que sumen 100).
	Weight: number,
	Kind: string,
	-- Imagen de la tarjeta. Sin Icon se muestra el modelo de CrateAssets.Rewards/<caja>/<Id>.
	Icon: string?,
}

export type Case = {
	Name: string,
	Cash: number,
	Gems: number,
	LuckyGems: number,
	Rewards: { Reward },
}

CrateConfig.CaseOrder = { "Effects", "Limited", "Snipers" }

CrateConfig.Cases = {
	Effects = {
		Name = "Basic Effect Case",
		Cash = 2800,
		Gems = 5,
		LuckyGems = 50,
		Rewards = {
			-- Íconos provisorios del Free Icon Pack: reemplazar por el arte final de cada efecto.
			{ Id = "Ruby", Name = "Ruby", Rarity = "Uncommon", Weight = 55, Kind = "Effect", Icon = "rbxassetid://135809263575904" },
			{ Id = "Flame", Name = "Flame", Rarity = "Rare", Weight = 25, Kind = "Effect", Icon = "rbxassetid://71681614248503" },
			{ Id = "Void", Name = "Void", Rarity = "Epic", Weight = 15, Kind = "Effect", Icon = "rbxassetid://101114951627972" },
			{ Id = "Candy", Name = "Candy", Rarity = "Legendary", Weight = 2, Kind = "Effect", Icon = "rbxassetid://116438802562785" },
			{ Id = "Diamond", Name = "Diamond", Rarity = "Legendary", Weight = 2, Kind = "Effect", Icon = "rbxassetid://79587407655510" },
			{ Id = "Golden", Name = "Golden", Rarity = "Mythic", Weight = 1, Kind = "Effect", Icon = "rbxassetid://83507327367131" },
		},
	},
	Snipers = {
		Name = "Basic Sniper Case",
		Cash = 3500,
		Gems = 5,
		LuckyGems = 50,
		Rewards = {
			{ Id = "Blue", Name = "Blue", Rarity = "Uncommon", Weight = 13.7225, Kind = "Sniper" },
			{ Id = "Green", Name = "Green", Rarity = "Uncommon", Weight = 13.7225, Kind = "Sniper" },
			{ Id = "Purple", Name = "Purple", Rarity = "Uncommon", Weight = 13.7225, Kind = "Sniper" },
			{ Id = "Red", Name = "Red", Rarity = "Uncommon", Weight = 13.7225, Kind = "Sniper" },
			{ Id = "Gilded", Name = "Gilded", Rarity = "Rare", Weight = 10, Kind = "Sniper" },
			{ Id = "Sky", Name = "Sky", Rarity = "Rare", Weight = 8, Kind = "Sniper" },
			{ Id = "Sweet", Name = "Sweet", Rarity = "Rare", Weight = 7, Kind = "Sniper" },
			{ Id = "Velvet", Name = "Velvet", Rarity = "Epic", Weight = 15, Kind = "Sniper" },
			{ Id = "Frost", Name = "Frost", Rarity = "Legendary", Weight = 4, Kind = "Sniper" },
			{ Id = "Dragon", Name = "Dragon", Rarity = "Mythic", Weight = 1, Kind = "Sniper" },
			{ Id = "DragonShot", Name = "Dragon Shot", Rarity = "Secret", Weight = 0.1, Kind = "Sniper" },
			{ Id = "Abyss", Name = "Abyss", Rarity = "Abyssal", Weight = 0.01, Kind = "Sniper" },
		},
	},
	Limited = {
		Name = "Limited Case",
		Cash = 5000,
		Gems = 15,
		LuckyGems = 150,
		Rewards = {
			{ Id = "Peachy", Name = "Peachy", Rarity = "Uncommon", Weight = 55, Kind = "Sniper" },
			{ Id = "Garand", Name = "M1 Garand", Rarity = "Rare", Weight = 25, Kind = "Sniper" },
			{ Id = "Bread", Name = "Bread", Rarity = "Epic", Weight = 15, Kind = "Sniper" },
			{ Id = "DeathRay", Name = "Death Ray", Rarity = "Legendary", Weight = 4, Kind = "Sniper" },
			{ Id = "Pulsar", Name = "Pulsar", Rarity = "Mythic", Weight = 1, Kind = "Sniper" },
		},
	},
} :: { [string]: Case }

function CrateConfig.Weight(reward: Reward, lucky: boolean?): number
	return reward.Weight * (if lucky then CrateConfig.LuckyMultipliers[reward.Rarity] or 1 else 1)
end

function CrateConfig.Reward(caseId: string, rewardId: string): Reward?
	local case = CrateConfig.Cases[caseId]
	for _, reward in if case then case.Rewards else {} do
		if reward.Id == rewardId then
			return reward
		end
	end
	return nil
end

-- Sorteo ponderado. `random` es opcional (el servidor pasa el suyo).
function CrateConfig.Pick(caseId: string, lucky: boolean?, random: Random?): Reward
	local rewards = CrateConfig.Cases[caseId].Rewards
	local total = 0
	for _, reward in rewards do
		total += CrateConfig.Weight(reward, lucky)
	end
	local choice = (random or Random.new()):NextNumber(0, total)
	for _, reward in rewards do
		choice -= CrateConfig.Weight(reward, lucky)
		if choice <= 0 then
			return reward
		end
	end
	return rewards[#rewards]
end

-- Porcentaje de cada rareza y el peso total (para el % de cada premio).
function CrateConfig.Odds(caseId: string, lucky: boolean?): ({ [string]: number }, number)
	local totals, total = {}, 0
	for _, reward in CrateConfig.Cases[caseId].Rewards do
		local weight = CrateConfig.Weight(reward, lucky)
		total += weight
		totals[reward.Rarity] = (totals[reward.Rarity] or 0) + weight
	end
	for rarity, weight in totals do
		totals[rarity] = weight / total * 100
	end
	return totals, total
end

return CrateConfig
