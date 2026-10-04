-- Ubicación en Studio: ServerScriptService > Services > Codes > CodesConfig (ModuleScript)
-- Catálogo privado del servidor: fuera de ReplicatedStorage para que no se filtren los códigos.
return {
	DataStoreName = "CodeRewards_v1",
	Cooldown = 1,
	Codes = {
		TEST = { Demo = true, Message = "Test code redeemed!" },
		-- Ejemplo inactivo. ExpiresAt es Unix UTC; nil significa sin expiración.
		-- RELEASE={Enabled=true,ExpiresAt=1893456000,
		--  Rewards={{Type="Cash",Amount=500},{Type="Item",Id="BasicCase",Amount=1}},
		--  Message="Claimed $500 Cash + 1 Basic Case!"},
	},
}
