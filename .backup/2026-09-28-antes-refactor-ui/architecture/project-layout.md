# Estructura del proyecto

## Folder mapping (default.project.json)

| Local folder          | Roblox                             | Use                                            |
|------------------------|-------------------------------------|-------------------------------------------------|
| `src/ReplicatedFirst`  | ReplicatedFirst                    | LoadingScreen (corre antes que nada replique)   |
| `src/Shared`           | ReplicatedStorage                  | Código y configs compartidos cliente/servidor   |
| `src/Server`           | ServerScriptService                | Lógica de servidor, Services                    |
| `src/ServerStorage`    | ServerStorage                      | EasyProfileStore, Maps (assets server-only)     |
| `src/StarterGui`       | StarterGui                         | UI (ScreenGuis armadas en Studio)               |
| `src/Client`           | StarterPlayer.StarterPlayerScripts | Input, cámara, UI del lado del cliente          |

Sincronización con Roblox Studio vía Argon:

```bash
argon serve   # sincronizar en vivo con Studio
argon build   # compilar el place
```

## Sistemas traídos de UBG (otro proyecto)

Se portaron 5 sistemas de UBG, adaptados para no depender de su sistema de rondas
de bomba (`GameRoundSystem`/`RoundEvents`, que NO se trajo):

- **EasyProfileStore** (`ServerStorage/EasyProfileStore`) — wrapper genérico sobre
  ProfileStore. No tiene ninguna llamada todavía (`SaveData.server.luau` de UBG,
  que definía el template de perfil, quedó afuera a propósito): hay que llamar
  `EasyProfileStore.New(nombre, template)` y `.onPlayerJoined(...)` desde donde
  arranque la persistencia de BloxDrivers.
- **NPC system** (`Shared/NPCConfig.luau` + `Shared/SimulatorCircleConfig.luau` +
  `Server/Services/Npc/*` + `Client/Controllers/NPC{Look,Zone}Controller`) — un
  NPC es cualquier Model con Humanoid dentro de `Workspace.SimulatorCircles/<Ring>/`;
  el nombre "SimulatorCircles" es el de UBG (rings de su lobby) y sigue siendo la
  carpeta que discovery espera — renombrala en `SimulatorCircleConfig.FolderName`
  si no encaja con el layout de BloxDrivers. La animación de láser del ring
  (`SimulatorCircleController`) NO se trajo, es solo decorativa.
- **Map Vote** (`Shared/VotingMapConfig.luau` + `Shared/MapVote/MapVoteBoard.luau`
  + `Server/Services/MapVote/MapVoteService.luau` + `StarterGui/VotingMapGui/*`) —
  desacoplado de rondas: `MapVoteService.runVoteWindow(duration)` dispara la
  ventana entera por `GameRemotes.fireAll`. Llamalo desde donde tenga sentido en
  BloxDrivers (ej. entre carreras). Lee el catálogo de `ServerStorage.Maps` (ver
  su README). `MapVoteBoard.luau` no lo usa nadie todavía (en UBG era para un
  holograma de pared que nunca se conectó) — lo mismo sirve como base para una
  segunda vista de solo lectura.
- **Topbar** (`Shared/TopbarPlus/**` + `Shared/TopbarConfig.luau` +
  `Client/Controllers/TopbarIcons.client.luau`) — se trajo la librería completa
  (TopbarPlus, de terceros) y el patrón `TopbarConfig.apply(icon, nombre)`, pero
  `TopbarConfig.Icons` quedó VACÍO: los íconos de UBG (Shop, Emotes, Spectate,
  etc.) no aplican a BloxDrivers. `TopbarIcons.client.luau` es el rework de
  `TopbarPlusIconCreator.client.luau` de UBG, recortado a lo único que usamos hoy:
  un ícono de debug (solo Studio) que dispara `GameRemotes.DebugMapVote` para
  correr la ventana de Map Vote REAL contra el servidor (distinto del ícono
  "Map Vote (Debug)" de `VotingMapClient`, que simula todo local). Sumá el
  primer ícono de producción (con su entrada en `TopbarConfig.Icons`) cuando
  tengas una feature real para colgarle.
- **LoadingScreen** (`ReplicatedFirst/LoadingScreen/*` + `Shared/{MenuCameraConfig,
  WaveTransitionConfig,PreloadAssets}.luau` + `Shared/UIHelpers.luau` + `Shared/DebugConfig.luau`
  + `Shared/Remotes/GameRemotes.luau` + `Server/Services/Loading/ServerAssetManifest.server.luau`)
  — el manifest resuelve el warn "Sin ServerAssetManifest": barre `ServerStorage`
  entero y publica sus asset IDs en `ReplicatedStorage.ServerAssetManifest` (un
  StringValue) para que la pantalla de carga los precargue de entrada. **Requiere
  un `LoadingGui` armado a mano
  en Studio** como hijo de `ReplicatedFirst.LoadingScreen` (Argon no sincroniza
  GUIs visuales): `Background > Center > SkipButton` + `TipFrame > TipLabel`, más
  opcionalmente un `Logo` (ImageLabel). Sin eso, `LoadingScript` se cuelga en el
  primer `WaitForChild`. La cámara del menú (`MenuCamera`) es tolerante: si no
  encuentra `Workspace.Lobby.CameraPoint` (o `.LobbySpawn`) sigue con el fondo
  opaco en vez de fallar. `VotingMapGui` (StarterGui) tiene la misma restricción:
  necesita `Panel > Cards (+ UIListLayout) > MapCard` armados en Studio.

Todos los IDs de sonido/música (click de UI en `UIHelpers`, música de menú + click
en `LoadingScript`, ola de cierre en `WaveTransitionConfig`, drop/tick/ganador en
`VotingMapClient`) quedaron con los MISMOS assets que UBG, a pedido — son de la
cuenta de UBG, así que si algún ID da error de permisos en BloxDrivers (asset
privado de otra cuenta/juego), hay que resubirlo o reemplazarlo por uno propio.

`Server/Main.server.luau` es el único punto que `require`-ea `MapVoteService`
(los `.server.luau` de `Npc` ya corren solos como Script). Sumá ahí cualquier
otro módulo de servicio nuevo que necesite activarse igual.
