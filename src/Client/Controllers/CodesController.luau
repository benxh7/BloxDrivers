-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > CodesController (ModuleScript)
-- Ventana "Codes": canjea con RedeemCode; el servidor valida y responde {Ok, Message}.
local RS = game:GetService("ReplicatedStorage")
local UIManager = require(script.Parent.UIManager)
local UIEffects = require(script.Parent.Parent.Utils.UIEffects)
local Notifications = require(script.Parent.Parent.Utils.Notifications)
local Remotes = require(RS:WaitForChild("Remotes"))
local Controller = {}
function Controller.Init()
	local gui = UIManager.WaitForGui("CodesGui")
	local main = gui.Main
	local input = main.CodeInput
	local button = main.RedeemSlot.RedeemButton
	local busy = false
	local function redeem()
		if busy then
			return
		end
		busy = true
		button.Label.Text = "..."
		local ok, response = pcall(function()
			return Remotes.func("RedeemCode"):InvokeServer(input.Text)
		end)
		busy = false
		button.Label.Text = "Redeem"
		if not ok or type(response) ~= "table" then
			Notifications.Show("Unable to redeem. Please try again.", { Theme = "Error" })
			return
		end
		Notifications.Show(response.Message, {
			Theme = if response.Ok then "Success" else "Error",
			SoundId = if response.Ok then "rbxassetid://109742263473623" else nil,
		})
		if response.Ok then
			input.Text = ""
		end
	end
	UIManager.Register("Codes", main, { HiddenScale = 0.1, OpenDuration = 0.35 })
	UIEffects.bindButton(button, redeem)
	UIEffects.bindHover(button, { Scale = 1.06, Rotation = 5, Duration = 0.14 })
	UIEffects.bindHover(main.Header.CloseButton, { Scale = 1.08, Rotation = 5, Duration = 0.14 })
	input.FocusLost:Connect(function(enter)
		if enter then
			redeem()
		end
	end)
	local setBlur = UIEffects.makeBlur("CodesBlur", 16, 0.2)
	UIManager.OnOpened("Codes", function()
		setBlur(true)
		UIEffects.playSound("rbxassetid://139719503904449", 0.5)
	end)
	UIManager.OnClosed("Codes", function()
		input:ReleaseFocus()
		setBlur(false)
	end)
	-- Solo achica en pantallas chicas: el tamaño diseñado en StarterGui es la base.
	local authored = main.Size
	local function fit()
		local screen = gui.AbsoluteSize
		local scale = math.min(1, screen.X * 0.84 / authored.X.Offset, screen.Y * 0.80 / authored.Y.Offset)
		main.Size = UDim2.fromOffset(authored.X.Offset * scale, authored.Y.Offset * scale)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	gui:SetAttribute("ControllerReady", true)
end
return Controller
