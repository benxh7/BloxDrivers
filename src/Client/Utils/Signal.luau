-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Utils > Signal (ModuleScript)
-- Señal estilo RBXScriptSignal. No BindableEvent: ese copia las tablas y no pasa funciones.
local Signal = {}
Signal.__index = Signal

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Listener = { Connected: boolean, callback: (...any) -> (), signal: any }

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local listeners = self.signal._listeners
	local index = table.find(listeners, self)
	if index then
		table.remove(listeners, index)
	end
end

function Signal.new(): Signal<...any>
	return setmetatable({ _listeners = {} :: { Listener } }, Signal) :: any
end

function Signal:Connect(callback: (...any) -> ()): Connection
	local connection = setmetatable({ Connected = true, callback = callback, signal = self }, Connection)
	table.insert(self._listeners, connection)
	return connection :: any
end

function Signal:Once(callback: (...any) -> ()): Connection
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

-- Cada listener en su hilo: si uno falla, los demás corren igual.
function Signal:Fire(...: any)
	-- Copia: un listener que se desconecta durante el Fire no corre el índice.
	for _, listener in table.clone(self._listeners) do
		if listener.Connected then
			task.spawn(listener.callback, ...)
		end
	end
end

function Signal:DisconnectAll()
	for _, listener in self._listeners do
		listener.Connected = false
	end
	table.clear(self._listeners)
end

return Signal
