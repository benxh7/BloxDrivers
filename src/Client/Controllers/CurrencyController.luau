-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > CurrencyController (ModuleScript)
-- Panel Cash/Gems del HUD: muestra leaderstats (o el atributo) y "+" abre la sección de la tienda.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local UIManager = require(script.Parent.UIManager)
local Shop = require(script.Parent.ShopController)
local UIEffects = require(script.Parent.Parent.Utils.UIEffects)
local Controller = {}
function Controller.Format(value)
	value = if type(value) == "number" and value == value then math.max(0, math.min(value, 1e15)) else 0
	for _, unit in { { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
		if value >= unit[1] then
			return (string.format("%.1f", math.floor(value / unit[1] * 10) / 10):gsub("%.0$", "")) .. unit[2]
		end
	end
	return tostring(math.floor(value))
end
function Controller.Init()
	local p = Players.LocalPlayer
	local gui = UIManager.WaitForGui("HUD")
	local panel = gui:WaitForChild("Currency")
	local holder = gui.LeftButtons
	local function position()
		if UserInputService.TouchEnabled or gui:GetAttribute("MobileHUDLayout") then
			return
		end
		panel.Position = UDim2.new(
			holder.Position.X.Scale,
			holder.Position.X.Offset,
			holder.Position.Y.Scale,
			holder.Position.Y.Offset - holder.AbsoluteSize.Y * holder.AnchorPoint.Y - 14
		)
	end
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(position)
	holder:GetPropertyChangedSignal("Position"):Connect(position)
	position()
	for _, name in { "Cash", "Gems" } do
		local row = panel[name]
		local valueConnection
		local function update()
			local stats = p:FindFirstChild("leaderstats")
			local stat = stats and stats:FindFirstChild(name)
			local amount = if stat and (stat:IsA("IntValue") or stat:IsA("NumberValue"))
				then stat.Value
				else p:GetAttribute(name)
			row.Amount.Text = Controller.Format(amount)
		end
		local function bindValue()
			if valueConnection then
				valueConnection:Disconnect()
				valueConnection = nil
			end
			local stats = p:FindFirstChild("leaderstats")
			local stat = stats and stats:FindFirstChild(name)
			if stat and (stat:IsA("IntValue") or stat:IsA("NumberValue")) then
				valueConnection = stat.Changed:Connect(update)
			end
			update()
		end
		local addConnection, removeConnection
		local function bindStats()
			if addConnection then
				addConnection:Disconnect()
				removeConnection:Disconnect()
			end
			local stats = p:FindFirstChild("leaderstats")
			if stats then
				addConnection = stats.ChildAdded:Connect(bindValue)
				removeConnection = stats.ChildRemoved:Connect(bindValue)
			else
				addConnection = nil
				removeConnection = nil
			end
			bindValue()
		end
		p.ChildAdded:Connect(function(o)
			if o.Name == "leaderstats" then
				bindStats()
			end
		end)
		p.ChildRemoved:Connect(function(o)
			if o.Name == "leaderstats" then
				bindStats()
			end
		end)
		p:GetAttributeChangedSignal(name):Connect(update)
		bindStats()
		UIEffects.bindButton(row.PlusSlot.Plus, function()
			Shop.OpenSection(name)
		end)
		UIEffects.bindHover(row.PlusSlot.Plus, { Scale = 1.08, Rotation = 5, Duration = 0.14 })
	end
end
return Controller
