-- Ubicación en Studio: ServerStorage > EasyProfileStore (ModuleScript)
-- Wrapper sobre ProfileStore: se usa con New(nombre, template) y onPlayerJoined desde un DataService.
local EasyProfileStore = {}
EasyProfileStore.__index = EasyProfileStore

local Players = game:GetService("Players")

local self = setmetatable({}, EasyProfileStore)

EasyProfileStore.DatasLoaded = nil
EasyProfileStore.TemplateDB = {}
EasyProfileStore.Profiles = {}

EasyProfileStore.BindableError = Instance.new("BindableEvent")
EasyProfileStore.OnError = EasyProfileStore.BindableError.Event

EasyProfileStore.BindableMessage = Instance.new("BindableEvent")
EasyProfileStore.SuscribeMessage = EasyProfileStore.BindableMessage.Event

local ProfileStore = require(script:FindFirstChild("ProfileStore"))

type PublishMessage = {
	UserId: number,
	Message: string
}

type SuscribeMessageType = {
	Player: Player,
	Message: string,
	Processed: RBXScriptSignal
}

function EasyProfileStore:_FireError(message : string)
	if not self.BindableError then
		return false
	end
	
	self.BindableError:Fire(message)
end

function EasyProfileStore.New(NameDB : string, template : any)
	if self.TemplateDB[NameDB] then
		EasyProfileStore:_FireError("Database already exists")
		return false
	end

	self.TemplateDB[NameDB] = template
	EasyProfileStore.DatasLoaded = ProfileStore.New(NameDB, template)
end

function EasyProfileStore:PublishMessage(UserId : number, Message : {})
	if not EasyProfileStore.DatasLoaded then
		return EasyProfileStore._FireError("Data not loaded")
	end
	
	if not UserId then
		self:_FireError("Missing UserId")
		return
	end

	if not Message then
		self:_FireError("Missing Message")
		return
	end
	
	if typeof(UserId) ~= "number" then
		self:_FireError("UserId must be a number")
		return
	end
	
	if typeof(Message) ~= "table" then
		self:_FireError("Message must be a table")
		return
	end
	EasyProfileStore.DatasLoaded:MessageAsync(`Player_{UserId}`,Message)
end

function EasyProfileStore.onPlayerJoined(callback : (Player, any) -> ())
	if not EasyProfileStore.DatasLoaded then
		return EasyProfileStore._FireError("Data not loaded")
	end
	
	Players.PlayerAdded:Connect(function(player)
		local profile = self.DatasLoaded:StartSessionAsync(
			`Player_{player.UserId}`,
			{
				Cancel = function()
					return player.Parent ~= Players
				end,
			}
		)

		if not profile then
			player:Kick("Profile load failed - Please rejoin")
			return
		end

		profile:AddUserId(player.UserId)
		profile:Reconcile()

		profile.OnSessionEnd:Connect(function()
			self.Profiles[player] = nil
			player:Kick("Profile session ended - Please rejoin")
		end)

		if player.Parent ~= Players then
			profile:EndSession()
			return
		end

		self.Profiles[player] = profile
		print(`Profile loaded for {player.DisplayName}!`)

		profile:MessageHandler(function(message, processed)
			self.BindableMessage:Fire(player,message,processed)
		end)

		callback(player, profile)
	end)
end

function EasyProfileStore.GetProfile(Player) : {Player}
	if not EasyProfileStore.DatasLoaded then
		return EasyProfileStore._FireError("Data not loaded")
	end
	
	if not Player then
		return self._FireError("Player not found")
	end
	
	if not self.Profiles[Player] then
		return self._FireError("Profile not found")
	end
	
	return self.Profiles[Player]
end

function EasyProfileStore.onPlayerRemoved(callback : (Player) -> ())
	if not self._FireError then
		return false
	end
	
	if not EasyProfileStore.DatasLoaded then
		return EasyProfileStore._FireError("Data not loaded")
	end
	
	Players.PlayerRemoving:Connect(function(player)
		if self.Profiles[player] then
			self.Profiles[player]:EndSession()
			self.Profiles[player] = nil;
			callback(player)
		end
	end)
end

return EasyProfileStore
