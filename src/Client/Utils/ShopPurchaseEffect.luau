-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Utils > ShopPurchaseEffect (ModuleScript)
-- Animación de compra (ShopPurchaseGui) antes del prompt de Roblox; ajustes por atributos de la GUI.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Marketplace = game:GetService("MarketplaceService")
local Input = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local Remotes = require(RS:WaitForChild("Remotes"))
local Effect = {}
local gui, root, center, border
local active
local generation = 0
local rotation
local transitions = {}
local function tween(o, seconds, props, style)
	local t =
		TweenService:Create(o, TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, Enum.EasingDirection.Out), props)
	table.insert(transitions, t)
	t:Play()
	return t
end
local function cancelTransitions()
	for _, t in transitions do
		t:Cancel()
	end
	table.clear(transitions)
end
local function restoreContext(state)
	if state.Camera and state.Camera.Parent then
		state.Camera.FieldOfView = state.FieldOfView
	end
	if state.Shop and state.Shop.Parent then
		state.Shop.Visible = state.ShopVisible
	end
	if state.Blur and state.Blur.Parent then
		state.Blur.Size = state.BlurSize
	end
end
function Effect.Stop()
	if not active or active.Closing then
		return
	end
	active.Closing = true
	generation += 1
	local token = generation
	local state = active
	cancelTransitions()
	if state.Camera and state.Camera.Parent then
		tween(state.Camera, 0.22, { FieldOfView = state.FieldOfView })
	end
	root:SetAttribute("Phase", "Closing")
	tween(border, 0.22, { GroupTransparency = 1 })
	tween(center, 0.18, { GroupTransparency = 1 })
	tween(root.Blocker, 0.22, { BackgroundTransparency = 1 })
	task.delay(0.23, function()
		if generation ~= token then
			return
		end
		root.Visible = false
		if rotation then
			rotation:Cancel()
		end
		restoreContext(state)
		cancelTransitions()
		active = nil
		root:SetAttribute("Phase", "Idle")
	end)
end
local function setup()
	if gui then
		return
	end
	gui = Players.LocalPlayer.PlayerGui:WaitForChild("ShopPurchaseGui")
	root = gui.Root
	center = root.Center
	border = root.ChromaBorder
	local function fit()
		local s = gui.AbsoluteSize
		center.ResponsiveScale.Scale = math.min(1, math.max(0.35, math.min((s.X - 32) / 480, (s.Y - 48) / 250)))
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	center.Close.Activated:Connect(Effect.Stop)
	Input.InputBegan:Connect(function(input, processed)
		if
			not processed
			and active
			and active.Preview
			and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB)
		then
			Effect.Stop()
		end
	end)
	Marketplace.PromptProductPurchaseFinished:Connect(function(userId, id)
		if active and userId == Players.LocalPlayer.UserId and active.Kind == "Product" and id == active.ProductId then
			Effect.Stop()
		end
	end)
	Marketplace.PromptGamePassPurchaseFinished:Connect(function(player, id)
		if active and player == Players.LocalPlayer and active.Kind == "GamePass" and id == active.ProductId then
			Effect.Stop()
		end
	end)
	Remotes.onUpdate("shopPromptFailed", function(id)
		if active and active.ItemId == id then
			Effect.Stop()
		end
	end)
	Remotes.onUpdate("shopPromptOpened", function(id)
		if active and active.ItemId == id then
			active.Opened = true
		end
	end)
	gui.Destroying:Connect(function()
		generation += 1
		cancelTransitions()
		if rotation then
			rotation:Cancel()
		end
		if active then
			restoreContext(active)
		end
		active = nil
		gui = nil
	end)
end
function Effect.Start(itemId, item, requestPurchase)
	setup()
	if active then
		return false
	end
	cancelTransitions()
	generation += 1
	local token = generation
	local speed = math.clamp(gui:GetAttribute("AnimationTimeScale") or 1.65, 0.5, 3)
	local preview = not item.ProductId or item.ProductId <= 0
	local camera = workspace.CurrentCamera
	local shopGui = Players.LocalPlayer.PlayerGui:FindFirstChild("ShopGui")
	local shop = shopGui and shopGui:FindFirstChild("Main")
	local blur = Lighting:FindFirstChild("ShopBlur")
	local state = {
		ItemId = itemId,
		ProductId = item.ProductId,
		Kind = item.Kind,
		Preview = preview,
		Camera = camera,
		FieldOfView = camera and camera.FieldOfView,
		Shop = shop,
		ShopVisible = shop and shop.Visible,
		Blur = blur,
		BlurSize = blur and blur.Size,
	}
	active = state
	if shop then
		shop.Visible = false
	end
	if blur then
		blur.Size = 0
	end
	root.Visible = true
	root.Blocker.BackgroundTransparency = 1
	center.Visible = true
	center.GroupTransparency = 0
	center.BackgroundTransparency = 1
	center.Close.Visible = false
	center.PreviewMessage.Visible = false
	center.Robux.Visible = true
	center.Robux.ImageTransparency = 0
	center.Robux.Rotation = 0
	center.Robux.Pop.Scale = 0.12
	border.GroupTransparency = 1
	border.Chroma.Rotation = 0
	if rotation then
		rotation:Cancel()
	end
	rotation = TweenService:Create(
		border.Chroma,
		TweenInfo.new(
			gui:GetAttribute("ChromaTurnSeconds") or 6,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.InOut,
			-1
		),
		{ Rotation = 360 }
	)
	rotation:Play()
	root:SetAttribute("Phase", "ZoomIn")
	tween(border, 0.25, { GroupTransparency = gui:GetAttribute("ChromaTransparency") or 0.4 })
	if camera then
		tween(
			camera,
			0.24 * speed,
			{ FieldOfView = math.max(20, state.FieldOfView - (gui:GetAttribute("ZoomDegrees") or 6)) }
		)
	end
	-- El símbolo crece, se asienta y se encoge mientras la cámara vuelve.
	tween(center.Robux.Pop, 0.23 * speed, { Scale = 1.14 }, Enum.EasingStyle.Cubic)
	task.delay(0.23 * speed, function()
		if generation ~= token or active ~= state then
			return
		end
		root:SetAttribute("Phase", "PopSettle")
		tween(center.Robux.Pop, 0.16 * speed, { Scale = 0.92 })
	end)
	task.delay(0.4 * speed, function()
		if generation ~= token or active ~= state then
			return
		end
		root:SetAttribute("Phase", "ZoomOut")
		if camera and camera.Parent then
			tween(camera, 0.36 * speed, { FieldOfView = state.FieldOfView })
		end
		tween(center.Robux.Pop, 0.28 * speed, { Scale = 0.05 }, Enum.EasingStyle.Quad)
		tween(center.Robux, 0.25 * speed, { ImageTransparency = 1 })
	end)
	task.delay(0.78 * speed, function()
		if generation ~= token or active ~= state then
			return
		end
		if camera and camera.Parent then
			camera.FieldOfView = state.FieldOfView
		end
		center.Robux.Visible = false
		root:SetAttribute("Phase", if preview then "Preview" else "PurchasePrompt")
		if preview then
			-- Mensaje explicativo simple: nunca imitar el diálogo de pago de Roblox.
			center.PreviewMessage.Visible = true
			center.Close.Visible = true
			center.GroupTransparency = 1
			tween(center, 0.18, { GroupTransparency = 0 })
			tween(root.Blocker, 0.18, { BackgroundTransparency = 0.6 })
		else
			center.Visible = false
			local ok, err = pcall(requestPurchase)
			if not ok then
				warn("[PurchaseEffect] " .. tostring(err))
				Effect.Stop()
				return
			end
			task.delay(30, function()
				if generation == token and active == state and not state.Opened then
					Effect.Stop()
				end
			end)
		end
	end)
	return true
end
return Effect
