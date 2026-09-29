-- Tunables de la cámara del menú de carga (la mueve
-- ReplicatedFirst/LoadingScreen/MenuCamera). Único lugar para retocar el encuadre.
local MenuCameraConfig = {}

-- Punto del lobby alrededor del cual orbita, buscado bajo Workspace. Si no está,
-- se cae al fallback: sin esto la pantalla quedaría con el fondo opaco para siempre.
MenuCameraConfig.TargetPath = { "Lobby", "CameraPoint" }
MenuCameraConfig.FallbackPath = { "Lobby", "LobbySpawn" }

-- Segundos de una vuelta completa. Más alto = más lento.
MenuCameraConfig.OrbitSeconds = 60
-- Distancia horizontal al punto, altura de la cámara y altura a la que mira
-- (Height > LookHeight = la cámara mira hacia abajo).
MenuCameraConfig.Radius = 45
MenuCameraConfig.Height = 18
MenuCameraConfig.LookHeight = 4
MenuCameraConfig.FieldOfView = 65
-- Ángulo inicial en grados: desde dónde arranca la vuelta.
MenuCameraConfig.StartAngle = 0

-- Parallax: además de orbitar, la cámara se corre un poco hacia donde está el
-- mouse. Studs por pixel de distancia al centro de la pantalla, y tope en studs.
MenuCameraConfig.ParallaxFactor = 0.004
MenuCameraConfig.ParallaxMax = 4
-- Suavizado del seguimiento (0-1, más alto = más rígido). Corregido por
-- framerate: se siente igual a 30 que a 144 fps.
MenuCameraConfig.Smoothing = 0.2

-- Corremos desde ReplicatedFirst, así que el lobby puede no haber replicado
-- todavía: cuánto esperarlo antes de rendirse y dejar el fondo opaco.
MenuCameraConfig.WaitForTargetSeconds = 20
-- Fade del fondo que descubre la escena 3D, una vez la cámara ya está puesta.
MenuCameraConfig.RevealSeconds = 1.2

return MenuCameraConfig
