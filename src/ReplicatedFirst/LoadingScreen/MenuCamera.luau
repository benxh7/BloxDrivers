-- Ubicación en Studio: ReplicatedFirst > LoadingScreen > MenuCamera (ModuleScript)
-- Cámara del menú de carga: orbita sola un punto fijo del lobby.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("MenuCameraConfig"))

local MenuCamera = {}

local localPlayer = Players.LocalPlayer

local active = false
local renderConn: RBXScriptConnection? = nil
local previousFov: number? = nil

local function resolve(path: { string }): BasePart?
	local current: Instance = Workspace
	for _, name in path do
		local child = current:FindFirstChild(name)
		if not child then return nil end
		current = child
	end
	return current:IsA("BasePart") and current or nil
end

-- Bloquea hasta WaitForTargetSeconds esperando que el lobby replique.
local function waitForTarget(): BasePart?
	local deadline = os.clock() + Config.WaitForTargetSeconds
	repeat
		local part = resolve(Config.TargetPath) or resolve(Config.FallbackPath)
		if part then return part end
		task.wait(0.2)
	until os.clock() > deadline
	return nil
end

-- Al volver a Custom, CameraSubject no se restaura solo.
local function setCameraSubject(camera: Camera, character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	camera.CameraSubject = humanoid
	return true
end

function MenuCamera.isActive(): boolean
	return active
end

-- false si el lobby nunca apareció: el menú se queda con su fondo en vez del vacío.
function MenuCamera.start(): boolean
	MenuCamera.stop()

	local target = waitForTarget()
	if not target then return false end

	local camera = Workspace.CurrentCamera
	if not camera then return false end

	active = true
	previousFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Config.FieldOfView

	local yaw = math.rad(Config.StartAngle)
	local speed = math.pi * 2 / math.max(Config.OrbitSeconds, 0.1)
	-- nil el primer frame: arranca en el destino y no barre desde donde la dejó el motor.
	local current: CFrame? = nil

	renderConn = RunService.RenderStepped:Connect(function(deltaTime)
		yaw += speed * deltaTime

		local center = target.Position
		local orbit = Vector3.new(math.sin(yaw), 0, math.cos(yaw)) * Config.Radius
		local goal = CFrame.lookAt(
			center + orbit + Vector3.new(0, Config.Height, 0),
			center + Vector3.new(0, Config.LookHeight, 0)
		)

		-- En el espacio de la cámara (al orbitar, la X del mundo no es "la derecha"). Solo
		-- con mouse: sin él GetMouseLocation da (0,0) y quedaría clavado al tope.
		if UserInputService.MouseEnabled then
			local viewport = camera.ViewportSize
			local mouse = UserInputService:GetMouseLocation()
			local parallaxX = math.clamp((mouse.X - viewport.X / 2) * Config.ParallaxFactor, -Config.ParallaxMax, Config.ParallaxMax)
			local parallaxY = math.clamp((viewport.Y / 2 - mouse.Y) * Config.ParallaxFactor, -Config.ParallaxMax, Config.ParallaxMax)
			goal *= CFrame.new(parallaxX, parallaxY, 0)
		end

		-- Corregido por deltaTime: si no, suaviza más rápido con más fps.
		local alpha = 1 - (1 - Config.Smoothing) ^ (deltaTime * 60)
		current = if current then current:Lerp(goal, alpha) else goal
		camera.CFrame = current :: CFrame
	end)

	return true
end

function MenuCamera.stop()
	if not active then return end
	active = false

	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	if previousFov then
		camera.FieldOfView = previousFov
		previousFov = nil
	end
	camera.CameraType = Enum.CameraType.Custom

	if localPlayer.Character and setCameraSubject(camera, localPlayer.Character) then return end

	local connection: RBXScriptConnection
	connection = localPlayer.CharacterAdded:Connect(function(character)
		connection:Disconnect()
		task.wait()
		setCameraSubject(camera, character)
	end)
end

return MenuCamera
