-- Ubicación en Studio: ReplicatedFirst > LoadingScreen > PreloadRunner (ModuleScript)
-- Precarga una lista de IDs con ContentProvider y reporta el progreso.
local CP = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Assets = require(ReplicatedStorage:WaitForChild("PreloadAssets"))
local Runner = {}
-- 4 hilos en paralelo; un resultado por ID aunque PreloadAsync llame varias veces al callback.
function Runner.Run(ids, onProgress, seconds)
	local nextIndex, processed, failed = 0, 0, 0
	local finished = {}
	local deadline = os.clock() + (seconds or 60)
	local closed = false
	local function finish(i, success)
		if closed or finished[i] then
			return
		end
		finished[i] = true
		processed += 1
		if not success then
			failed += 1
		end
		onProgress(processed, #ids, failed)
	end
	for _ = 1, math.min(4, #ids) do
		task.spawn(function()
			while not closed do
				nextIndex += 1
				local i = nextIndex
				if i > #ids then
					return
				end
				local success = true
				local holder
				local ok, err = pcall(function()
					local kind = Assets.Kinds[ids[i]] or { Class = "ImageLabel", Property = "Image" }
					if kind.Class == "MeshPart" then
						kind = {
							Class = "SpecialMesh",
							Property = if kind.Property == "MeshId" then "MeshId" else "TextureId",
						}
					end
					holder = Instance.new(kind.Class)
					holder[kind.Property] = ids[i]
					CP:PreloadAsync({ holder }, function(_, status)
						if status ~= Enum.AssetFetchStatus.Success then
							success = false
						end
					end)
				end)
				if holder then
					holder:Destroy()
				end
				if not ok then
					warn("[PreloadRunner] " .. ids[i] .. ": " .. tostring(err))
				end
				finish(i, ok and success)
			end
		end)
	end
	while processed < #ids and os.clock() < deadline do
		task.wait(0.05)
	end
	local timedOut = #ids - processed
	closed = true
	return { Processed = processed, Total = #ids, Failed = failed, TimedOut = timedOut }
end
return Runner
