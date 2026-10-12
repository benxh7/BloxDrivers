-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > CrateController (ModuleScript)
-- Ventana de cajas (CrateGui): ruleta de premios, probabilidades, compras y tiradas.
-- El servidor sortea y guarda el premio; acá solo se anima hasta el resultado que llegó.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local ContentProvider = game:GetService("ContentProvider")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("CrateConfig"))
local Remotes = require(RS:WaitForChild("Remotes"))
local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local UITemplates = require(Utils:WaitForChild("UITemplates"))
local UIManager = require(script.Parent:WaitForChild("UIManager"))

local Controller = {}

local WINDOW = Config.WindowName
-- Tarjetas que se reciclan en la ruleta: las visibles más una de cada lado.
local SLOT_COUNT = 9
-- Margen al azar (px) para que la ganadora no frene siempre justo en el centro.
local LANDING_JITTER = 38

type State = "Closed" | "Idle" | "Requesting" | "Spinning" | "Revealing"

local gui: ScreenGui
local main: Frame
local controls: Frame
local step = Config.Reel.Step
local caseId = "Effects"
local state: State = "Closed"
-- Sube al cerrar o cambiar de caja: las animaciones y respuestas viejas se descartan solas.
local generation = 0
local sequence: { Config.Reward } = {}
local slots: { GuiObject } = {}
local expanded: { [string]: boolean } = {}
local showingLucky = false
local progress = Instance.new("NumberValue")
local spinTween: Tween?
local finishSpin: (() -> ())?
local lastTickIndex, lastTickAt = 0, 0
local tickSound: Sound?
local blur: (boolean) -> ()
local frameConnection: RBXScriptConnection?
local toastCount = 0
type ChestAnim = {
	Lid: Model,
	LidRest: CFrame,
	LidValue: CFrameValue,
	Light: PointLight?,
	LightRest: number,
	Treasure: Model?,
	TreasureRest: CFrame?,
	TreasureValue: CFrameValue?,
	Rise: number,
	Tweens: { Tween },
}
-- Cofre del lobby abierto mientras se ve la ruleta (solo lo ve este jugador).
local activeChest: ChestAnim?
-- Cierre animado en curso: abrir otro cofre (o el mismo) lo termina de golpe primero.
local closingChest: { Tweens: { Tween }, Finish: () -> () }?

local function amount(value: number): string
	if value >= 1000 then
		return (string.format("%.1fk", value / 1000):gsub("%.0k", "k"))
	end
	return tostring(value)
end

-- 54.89 -> "54.89%", 15 -> "15%", 0.01 -> "0.01%".
local function percent(value: number): string
	local text = string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", "")
	return text .. "%"
end

local function playSound(sound: { Id: string, Volume: number }?)
	if sound then
		UIEffects.playSound(sound.Id, sound.Volume)
	end
end

local function gradient(colors: { Color3 }): ColorSequence
	return ColorSequence.new(colors[1], colors[#colors])
end

local function toast(text: string, themeName: string)
	local label = UITemplates.clone("CrateToast") :: TextLabel?
	if not label then
		return
	end
	local theme = Config.ToastThemes[themeName]
	label.Text = text
	label.UIGradient.Color = gradient(theme.Colors)
	label.TextOutline.Color = theme.Stroke
	toastCount += 1
	label.LayoutOrder = toastCount
	label.Visible = true
	label.Parent = main.Toasts
	local shown = {}
	for _, child in main.Toasts:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(shown, child)
		end
	end
	table.sort(shown, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = 1, #shown - Config.Toast.MaxStacked do
		shown[index]:Destroy()
	end
	label.ToastScale.Scale = 0.8
	TweenService:Create(label.ToastScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(Config.Toast.Duration, function()
		if not label.Parent then
			return
		end
		local fade = TweenInfo.new(0.3)
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		local strokeFade = TweenService:Create(label.TextOutline, fade, { Transparency = 1 })
		strokeFade.Completed:Once(function()
			label:Destroy()
		end)
		strokeFade:Play()
	end)
end

local function showError(message: string)
	toast(message, "Error")
	playSound(Config.Sounds.Error)
end

local function invoke(action: string, option: any?): any?
	local ok, response = pcall(function()
		return Remotes.func("CrateRequest"):InvokeServer(action, caseId, option, HttpService:GenerateGUID(false))
	end)
	if not ok or type(response) ~= "table" then
		showError("Could not reach the server. Try again.")
		return nil
	end
	if not response.Ok then
		showError(response.Message or "The case could not be opened.")
		return nil
	end
	return response
end

local function showModel(viewport: ViewportFrame, reward: Config.Reward)
	viewport:ClearAllChildren()
	local folder = RS:FindFirstChild("CrateAssets")
	local model = folder and folder.Rewards[caseId]:FindFirstChild(reward.Id)
	if not model then
		return
	end
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local clone = model:Clone()
	clone.Parent = world
	local center, size = clone:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	-- Distancia para que el lado más largo entre en el FOV, con 8% de aire.
	local distance = math.max(size.X, size.Y) * 0.5 / math.tan(math.rad(16)) * 1.08
	camera.CFrame = CFrame.lookAt(center.Position + Vector3.new(0, 0.12, distance), center.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

local function paintCard(card: GuiObject, reward: Config.Reward)
	local color = Config.Rarities[reward.Rarity].Color
	-- El UIGradient multiplica el fondo blanco: arriba más claro, abajo más oscuro.
	card.UIGradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.3), color:Lerp(Color3.new(), 0.12))
	card.Outline.Color = color:Lerp(Color3.new(), 0.55)
	-- Borde ancho interior, más claro que el panel (como las tarjetas del video).
	card.Rim.UIStroke.Color = color:Lerp(Color3.new(1, 1, 1), 0.45)
	for _, layer in card.Glow:GetChildren() do
		local stroke = layer:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end
	end
	card.RewardName.Text = reward.Name
	local hasIcon = reward.Icon ~= nil
	local useEffect = not hasIcon and reward.Kind == "Effect"
	card.Icon.Visible = hasIcon
	card.Icon.Image = reward.Icon or ""
	card.EffectArtwork.Visible = useEffect
	card.Artwork.Visible = not hasIcon and not useEffect
	if useEffect then
		for _, piece in card.EffectArtwork:GetChildren() do
			if piece:IsA("ImageLabel") then
				-- Atributo Tint: -1..1, hacia negro o blanco desde el color de la rareza.
				local tint = piece:GetAttribute("Tint") or 0
				piece.ImageColor3 = color:Lerp(if tint < 0 then Color3.new() else Color3.new(1, 1, 1), math.abs(tint))
			end
		end
	elseif not hasIcon then
		showModel(card.Artwork, reward)
	end
end

local function drawReel()
	local center = math.floor(progress.Value / step)
	for offset = -4, 4 do
		local index = center + offset
		-- Cada índice cae siempre en el mismo slot: solo se repinta la tarjeta que entra por el borde.
		local card = slots[index % SLOT_COUNT + 1]
		local reward = sequence[index + 1]
		card.Visible = reward ~= nil
		if reward then
			local key = caseId .. ":" .. reward.Id
			if card:GetAttribute("RewardKey") ~= key then
				card:SetAttribute("RewardKey", key)
				paintCard(card, reward)
			end
			card.Position = UDim2.new(0.5, index * step - progress.Value, 0.5, 0)
		end
	end
	local now = os.clock()
	if state == "Spinning" and center ~= lastTickIndex and now - lastTickAt > Config.Sounds.Tick.MinGap then
		lastTickIndex, lastTickAt = center, now
		if tickSound then
			-- Una sola voz reiniciada: los ticks rápidos no se apilan en un ruido fuerte.
			tickSound.TimePosition = 0
			tickSound:Play()
		end
	end
end

local function drawOdds(lucky: boolean)
	showingLucky = lucky
	local list = main.Odds.List
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local totals, total = Config.Odds(caseId, lucky)
	local order = 0
	for _, rarity in Config.RarityOrder do
		if not totals[rarity] then
			continue
		end
		local style = Config.Rarities[rarity]
		local row = UITemplates.clone("CrateRarityRow")
		if not row then
			return
		end
		order += 1
		row.Name = rarity
		row.LayoutOrder = order
		row.Label.Text = ("%s - %s"):format(rarity, percent(totals[rarity]))
		row.Label.UIGradient.Color = ColorSequence.new(style.Color:Lerp(Color3.new(1, 1, 1), 0.35), style.Color)
		row.Label.Outline.Color = style.Stroke
		row.Visible = true
		row.Parent = list
		UIEffects.bindButton(row.Toggle, function()
			expanded[rarity] = not expanded[rarity]
			drawOdds(showingLucky)
		end)
		UIEffects.bindHover(row.Toggle, { Scale = 1.08 })
		if not expanded[rarity] then
			continue
		end
		for _, reward in Config.Cases[caseId].Rewards do
			if reward.Rarity == rarity then
				local detail = UITemplates.clone("CrateRewardOddsRow")
				if detail then
					order += 1
					detail.Name = reward.Id
					detail.LayoutOrder = order
					detail.Label.Text = ("%s - %s"):format(reward.Name, percent(Config.Weight(reward, lucky) / total * 100))
					detail.Visible = true
					detail.Parent = list
				end
			end
		end
	end
end

local function updateState(snapshot: any)
	if snapshot then
		main.Owned.Text = "Owned: " .. tostring(snapshot.Owned[caseId] or 0)
	end
end

local SPIN_HIDDEN = { "BuyGems1", "Spin", "BuyGems3", "BuyCash", "Gems1Price", "Gems3Price", "CashPrice", "CashIcon" }

-- Mientras gira solo queda SKIP en el lugar de SPIN; los LUCKY SPIN se ven pero no responden.
local function setSpinning(spinning: boolean)
	for _, name in SPIN_HIDDEN do
		controls[name].Visible = not spinning
	end
	controls.Skip.Visible = spinning
	controls.Lucky1.Active = not spinning
	controls.Lucky3.Active = not spinning
end

local function setState(value: State)
	state = value
	main:SetAttribute("State", value)
end

local function idleReel()
	local rewards = Config.Cases[caseId].Rewards
	sequence = {}
	-- Tres vueltas de la lista y un margen: el desliz en reposo vuelve atrás una vuelta sin cortes.
	for index = 1, #rewards * 3 + 10 do
		sequence[index] = rewards[(index - 1) % #rewards + 1]
	end
	progress.Value = 2 * step
	drawReel()
end

-- PivotTo no se puede tweenear directo: se anima un CFrameValue y se copia al modelo.
local function pivotDriver(model: Model, start: CFrame): CFrameValue
	local value = Instance.new("CFrameValue")
	value.Value = start
	value.Changed:Connect(function(cframe)
		if model.Parent then
			model:PivotTo(cframe)
		end
	end)
	model:PivotTo(start)
	return value
end

local function tween(object: Instance, seconds: number, style: Enum.EasingStyle, direction: Enum.EasingDirection, goal: { [string]: any }): Tween
	local created = TweenService:Create(object, TweenInfo.new(seconds, style, direction), goal)
	created:Play()
	return created
end

local function treasureParts(chest: ChestAnim): { BasePart }
	local parts = {}
	for _, part in if chest.Treasure then chest.Treasure:GetChildren() else {} do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	return parts
end

local function finishClosing()
	local closing = closingChest
	if closing then
		closingChest = nil
		for _, running in closing.Tweens do
			running:Cancel()
		end
		closing.Finish()
	end
end

-- instant = true deja el cofre cerrado de golpe.
local function closeChest(instant: boolean?)
	finishClosing()
	local chest = activeChest
	if not chest then
		return
	end
	activeChest = nil
	for _, running in chest.Tweens do
		running:Cancel()
	end
	-- Con señales diferidas el último Changed de un tween se pierde si el valor se destruye
	-- enseguida: el reposo se aplica a mano antes de limpiar.
	local function finish()
		if chest.Lid.Parent then
			chest.Lid:PivotTo(chest.LidRest)
		end
		if chest.Light then
			chest.Light.Brightness = chest.LightRest
		end
		if chest.Treasure and chest.TreasureRest and chest.Treasure.Parent then
			chest.Treasure:PivotTo(chest.TreasureRest)
		end
		for _, part in treasureParts(chest) do
			part.Transparency = 1
		end
		chest.LidValue:Destroy()
		if chest.TreasureValue then
			chest.TreasureValue:Destroy()
		end
	end
	if instant then
		finish()
		return
	end
	local seconds = Config.Chest.CloseSeconds
	local style, direction = Enum.EasingStyle.Quad, Enum.EasingDirection.In
	local tweens = { tween(chest.LidValue, seconds, style, direction, { Value = chest.LidRest }) }
	if chest.Light then
		table.insert(tweens, tween(chest.Light, seconds, style, direction, { Brightness = chest.LightRest }))
	end
	if chest.TreasureValue and chest.TreasureRest then
		table.insert(tweens, tween(chest.TreasureValue, seconds, style, direction, {
			Value = chest.TreasureRest - Vector3.new(0, chest.Rise, 0),
		}))
	end
	for _, part in treasureParts(chest) do
		table.insert(tweens, tween(part, seconds * 0.8, style, direction, { Transparency = 1 }))
	end
	local closing = { Tweens = tweens, Finish = finish }
	closingChest = closing
	tweens[1].Completed:Once(function(status)
		if status == Enum.PlaybackState.Completed and closingChest == closing then
			closingChest = nil
			finish()
		end
	end)
end

local function openChest(display: Instance?)
	closeChest(true)
	local model = display and display:FindFirstChild("Chest")
	local lid = model and model:FindFirstChild("Lid")
	if not (lid and lid:IsA("Model")) then
		return
	end
	local settings = Config.Chest
	local body = model:FindFirstChild("Body")
	local glow = body and body:FindFirstChild("InnerGlow")
	local light = glow and glow:FindFirstChildOfClass("PointLight")
	local treasure = model:FindFirstChild("Treasure")
	local chest: ChestAnim = {
		Lid = lid,
		LidRest = lid:GetPivot(),
		LidValue = pivotDriver(lid, lid:GetPivot()),
		Light = light,
		LightRest = if light then light.Brightness else 0,
		Treasure = if treasure and treasure:IsA("Model") then treasure else nil,
		TreasureRest = nil,
		TreasureValue = nil,
		Rise = 0,
		Tweens = {},
	}
	activeChest = chest
	table.insert(chest.Tweens, tween(chest.LidValue, settings.OpenSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out, {
		Value = chest.LidRest * CFrame.Angles(math.rad(-settings.OpenAngle), 0, 0),
	}))
	if light then
		table.insert(chest.Tweens, tween(light, settings.OpenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
			Brightness = chest.LightRest * settings.GlowBoost,
		}))
	end
	local sparkles = body and body:FindFirstChild("AmbientSparkles", true)
	if sparkles and sparkles:IsA("ParticleEmitter") then
		sparkles:Emit(settings.SparkBurst)
	end
	if chest.Treasure then
		-- En Studio quedan a su altura final e invisibles; Rise = cuánto suben desde adentro.
		chest.Rise = chest.Treasure:GetAttribute("Rise") or 0
		chest.TreasureRest = chest.Treasure:GetPivot()
		chest.TreasureValue = pivotDriver(chest.Treasure, chest.TreasureRest - Vector3.new(0, chest.Rise, 0))
		table.insert(chest.Tweens, tween(chest.TreasureValue, settings.OpenSeconds * 1.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out, {
			Value = chest.TreasureRest,
		}))
		for _, part in treasureParts(chest) do
			table.insert(chest.Tweens, tween(part, settings.OpenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
				Transparency = part:GetAttribute("ShownTransparency") or 0,
			}))
		end
	end
	playSound(Config.Sounds.LidOpen)
end

-- La tirada visual: rellena la ruleta al azar con los mismos pesos y pone el premio real en el centro.
local function rollOne(reward: Config.Reward, token: number, lucky: boolean, onDone: () -> ())
	local before = Config.Reel.CardsBeforeWinner
	sequence = {}
	for index = 1, before + 9 do
		sequence[index] = Config.Pick(caseId, lucky)
	end
	sequence[before + 1] = reward
	local target = before * step + Random.new():NextNumber(-LANDING_JITTER, LANDING_JITTER)
	setState("Spinning")
	setSpinning(true)
	progress.Value = 2 * step
	drawReel()

	local revealed = false
	local function reveal()
		if revealed or token ~= generation then
			return
		end
		revealed = true
		finishSpin = nil
		setState("Revealing")
		if tickSound then
			tickSound:Stop()
		end
		progress.Value = target
		drawReel()
		setSpinning(false)
		toast(("Rolled %s!"):format(reward.Name), "Win")
		playSound(Config.Sounds.Win[reward.Rarity] or Config.Sounds.Win.Default)
		main:SetAttribute("LastReward", reward.Id)
		task.delay(Config.Reel.RevealSeconds, function()
			if token == generation then
				onDone()
			end
		end)
	end

	local function tweenTo(seconds: number)
		if spinTween then
			spinTween:Cancel()
		end
		spinTween = TweenService:Create(progress, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Value = target })
		spinTween.Completed:Once(function(status)
			if status == Enum.PlaybackState.Completed then
				reveal()
			end
		end)
		spinTween:Play()
	end

	finishSpin = function()
		if state == "Spinning" and not revealed then
			tweenTo(Config.Reel.SkipSeconds)
		end
	end
	tweenTo(Config.Reel.SpinSeconds)
end

local function purchase(option: string)
	if state ~= "Idle" then
		return
	end
	local token = generation
	setState("Requesting")
	local response = invoke("Buy", option)
	if token ~= generation then
		return
	end
	setState("Idle")
	if response then
		updateState(response.State)
		playSound(Config.Sounds.Purchase)
		toast("Case added!", "Info")
	end
end

local function spin(lucky: boolean, count: number)
	if state ~= "Idle" then
		return
	end
	local token = generation
	setState("Requesting")
	local response = invoke(if lucky then "Lucky" else "Spin", count)
	if token ~= generation then
		return
	end
	if not response then
		setState("Idle")
		return
	end
	updateState(response.State)
	drawOdds(lucky)
	local index = 0
	local function nextRoll()
		index += 1
		local rewardId = response.Results[index]
		local reward = rewardId and Config.Reward(caseId, rewardId)
		if reward then
			rollOne(reward, token, lucky, nextRoll)
			return
		end
		setState("Idle")
		setSpinning(false)
		drawOdds(false)
		idleReel()
	end
	nextRoll()
end

local function onFrame(dt: number)
	if state == "Idle" then
		local loop = #Config.Cases[caseId].Rewards * step
		local value = progress.Value + math.min(dt, 0.1) * Config.Reel.IdleSpeed
		if value >= loop + 2 * step then
			value -= loop
		end
		progress.Value = value
	end
	local rotation = (os.clock() * Config.Reel.LuckyRotationSpeed) % 360
	controls.Lucky1.Face.UIGradient.Rotation = rotation
	controls.Lucky3.Face.UIGradient.Rotation = rotation
end

function Controller.Open(id: string, display: Instance?)
	local case = Config.Cases[id]
	if not case or (UIManager.IsOpen(WINDOW) and state ~= "Idle") then
		return
	end
	generation += 1
	local token = generation
	local ok, response = pcall(function()
		return Remotes.func("CrateRequest"):InvokeServer("State", id)
	end)
	if token ~= generation then
		return
	end
	if not ok or type(response) ~= "table" or not response.Ok then
		showError(if ok and type(response) == "table" and response.Message then response.Message else "Case server is unavailable.")
		return
	end
	caseId = id
	expanded = {}
	setState("Idle")
	main:SetAttribute("CaseId", id)
	main.Title.Text = case.Name
	controls.Gems1Price.Text = ("%d Gems"):format(case.Gems)
	controls.Gems3Price.Text = ("%d Gems"):format(case.Gems * 3)
	controls.CashPrice.Text = amount(case.Cash)
	controls.Lucky1Price.Text = ("%d Gems"):format(case.LuckyGems)
	controls.Lucky3Price.Text = ("%d Gems"):format(case.LuckyGems * 3)
	updateState(response.State)
	setSpinning(false)
	idleReel()
	drawOdds(false)
	openChest(display)
	UIManager.Open(WINDOW)
end

function Controller.Init()
	gui = UIManager.WaitForGui("CrateGui") :: ScreenGui
	main = gui:WaitForChild("Main") :: Frame
	controls = main:WaitForChild("Controls") :: Frame
	blur = UIEffects.makeBlur("CrateBlur", 18, 0.25)

	local tick = Config.Sounds.Tick
	tickSound = UIEffects.makeSound("CrateReelTick", tick.Id, tick.Volume)
	if tickSound then
		tickSound.PlaybackSpeed = tick.Speed
		task.spawn(pcall, ContentProvider.PreloadAsync, ContentProvider, { tickSound })
	end

	-- Main está diseñado a 1920x1008 en offset: se escala entero para entrar en la pantalla.
	local design = main.Size
	local function resize()
		local size = gui.AbsoluteSize
		main.ResponsiveScale.Scale = math.min(size.X / design.X.Offset, size.Y / design.Y.Offset)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	resize()

	for index = 1, SLOT_COUNT do
		local card = UITemplates.clone("CrateRewardCard")
		if card then
			card.Name = "Slot" .. index
			card.Parent = main.Reel.Clip
			slots[index] = card
		end
	end
	progress.Changed:Connect(drawReel)

	UIManager.Register(WINDOW, main, { Animate = false, CloseOnButtonB = true })
	UIManager.OnOpened(WINDOW, function()
		blur(true)
		if not frameConnection then
			frameConnection = RunService.RenderStepped:Connect(onFrame)
		end
	end)
	UIManager.OnClosed(WINDOW, function()
		generation += 1
		setState("Closed")
		if spinTween then
			spinTween:Cancel()
		end
		if tickSound then
			tickSound:Stop()
		end
		if frameConnection then
			frameConnection:Disconnect()
			frameConnection = nil
		end
		finishSpin = nil
		blur(false)
		closeChest()
		for _, child in main.Toasts:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
	end)

	local actions = {
		BuyGems1 = function() purchase("Gems1") end,
		BuyGems3 = function() purchase("Gems3") end,
		BuyCash = function() purchase("Cash1") end,
		Spin = function() spin(false, 1) end,
		Lucky1 = function() spin(true, 1) end,
		Lucky3 = function() spin(true, 3) end,
		Skip = function()
			if finishSpin then
				finishSpin()
			end
		end,
	}
	for name, callback in actions do
		local button = controls[name]
		UIEffects.bindButton(button, callback)
		UIEffects.bindHover(button, { Scale = 1.04, Rotation = 5 })
	end
	UIEffects.bindHover(main.CloseButton, { Scale = 1.04, Rotation = 5 })
	-- Con el mouse sobre LUCKY SPIN el panel muestra las probabilidades con suerte.
	for _, name in { "Lucky1", "Lucky3" } do
		controls[name].MouseEnter:Connect(function()
			if state == "Idle" then
				drawOdds(true)
			end
		end)
		controls[name].MouseLeave:Connect(function()
			if state == "Idle" then
				drawOdds(false)
			end
		end)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name ~= Config.PromptName then
			return
		end
		local id = prompt:GetAttribute("CaseId")
		-- El prompt vive en Chest > Body > Base: la vitrina es el ancestro que contiene a Chest.
		local display = prompt.Parent
		while display and display ~= workspace and not display:FindFirstChild("Chest") do
			display = display.Parent
		end
		if type(id) == "string" then
			Controller.Open(id, display)
		end
	end)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		UIManager.Close(WINDOW)
	end)
end

return Controller
