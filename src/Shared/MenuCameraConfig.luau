-- Ubicación en Studio: ReplicatedStorage > MenuCameraConfig (ModuleScript)
-- Encuadre de la cámara del menú de carga (la mueve LoadingScreen/MenuCamera).
local MenuCameraConfig = {}

-- Punto del lobby (bajo Workspace) alrededor del cual orbita. Sin ninguno de los dos,
-- el fondo de la carga queda opaco.
MenuCameraConfig.TargetPath = { "Lobby", "CameraPoint" }
MenuCameraConfig.FallbackPath = { "Lobby", "LobbySpawn" }

-- Segundos por vuelta completa (más alto = más lento).
MenuCameraConfig.OrbitSeconds = 60
-- Height > LookHeight = la cámara mira hacia abajo.
MenuCameraConfig.Radius = 45
MenuCameraConfig.Height = 18
MenuCameraConfig.LookHeight = 4
MenuCameraConfig.FieldOfView = 65
-- Grados desde donde arranca la vuelta.
MenuCameraConfig.StartAngle = 0

-- Parallax hacia el mouse: studs por pixel de distancia al centro, y tope en studs.
MenuCameraConfig.ParallaxFactor = 0.004
MenuCameraConfig.ParallaxMax = 4
-- 0-1, más alto = más rígido. Corregido por framerate.
MenuCameraConfig.Smoothing = 0.2

-- Corre desde ReplicatedFirst: el lobby puede no haber replicado todavía.
MenuCameraConfig.WaitForTargetSeconds = 20
-- Fade del fondo que descubre la escena 3D.
MenuCameraConfig.RevealSeconds = 1.2

return MenuCameraConfig
