# BloxDrivers

Juego de carreras en Roblox. El código vive en `src/` y se sincroniza con Roblox Studio
vía **Argon** (`default.project.json`). Lo visual de las GUIs (ScreenGuis y plantillas)
se diseña a mano en Studio; en disco solo va el código.

```bash
argon serve   # sincronizar en vivo con Studio
argon build   # compilar el place (sirve también para validar la estructura)
```

---

## Arquitectura

Todo se organiza en **pares con el mismo nombre** por sistema:

| Pieza | Ubicación en Studio | Carpeta local | Cuándo |
|---|---|---|---|
| `NombreGui` (ScreenGui, solo visual) | StarterGui | `src/StarterGui` | Siempre |
| `NombreController` (ModuleScript con `Init()`) | StarterPlayerScripts > Controllers | `src/Client/Controllers` | Siempre |
| `NombreConfig` (datos) | ReplicatedStorage | `src/Shared` | Si muestra listas |
| Plantillas (cards, slots, filas) | ReplicatedStorage > UITemplates | *(solo Studio)* | Si hay elementos repetidos |
| `NombreService` (ModuleScript con `Init()`) | ServerScriptService > Services | `src/Server/Services` | Si toca datos del jugador |
| Remotes | ReplicatedStorage > Remotes | `src/Shared/Remotes/init.luau` | Si el cliente pide algo |

Ejemplo: `InventoryGui` ↔ `InventoryController` ↔ `InventoryService` ↔ `InventoryConfig`.

### Estructura

```
ReplicatedFirst
└── LoadingScreen            pantalla de carga (corre antes que todo)

ReplicatedStorage            (src/Shared)
├── Remotes                  ModuleScript + RemoteEvents/Functions como hijos (los crea el server)
├── UITemplates              plantillas visuales — las creás vos en Studio
├── TopbarPlus               librería de terceros
├── DebugConfig, NPCConfig, VotingMapConfig, TopbarConfig, ...   (Configs)

ServerScriptService          (src/Server)
├── Main                     Script: crea Remotes y arranca todos los *Service
└── Services
    ├── Admin/AdminService (+ AdminRanks, AdminBroadcast)
    ├── Data/DataService     dueño de EasyProfileStore (perfil de cada jugador)
    ├── Codes/CodesService (+ CodesConfig, privado del servidor)
    ├── Loading/AssetManifestService, LoadingService
    ├── MapVote/MapVoteService
    ├── Npc/NPCAnimationService, NPCBillboardService, DialogueService
    ├── Shop/ShopService
    └── Spectator/SpectatorService (+ ReportConfig, ReportPolicy)

ServerStorage                (src/ServerStorage)
├── EasyProfileStore         wrapper de ProfileStore (persistencia, vía DataService)
└── Maps                     catálogo de mapas (Studio)

StarterPlayerScripts         (src/Client)
├── ClientMain               LocalScript: arranca todos los controllers
├── Controllers
│   ├── UIManager            ventanas (una abierta a la vez)
│   ├── HUDController, CurrencyController
│   ├── ShopController, SettingsController, CodesController
│   ├── DailyController, PlaytimeController, SpectatorController
│   ├── VotingMapController
│   ├── TopbarController
│   ├── NPCLookController, NPCZoneController
│   ├── DialogueController   diálogos de NPC (prompt "Talk" + retrato 3D)
│   ├── SimulatorCircleController   lasers de los aros del lobby
│   └── _TemplateController  plantilla para copiar (ignorada por ClientMain)
├── Components
│   └── MapVoteBoard         vista reutilizable de la votación (sin uso todavía)
└── Utils
    ├── UIEffects            popIn/popOut, pop de botón, sonidos, findChild
    ├── UITemplates          acceso a ReplicatedStorage.UITemplates
    ├── Signal               señales entre módulos
    ├── Notifications        toasts (plantilla UITemplates.ToastMessage)
    ├── MobileScaler         reacomodo del HUD en táctil
    ├── AnimatedDialogueText texto letra por letra (diálogos de NPC y anuncios)
    ├── ShopPurchaseEffect   animación previa al prompt de compra
    ├── WindowLayout         tamaño de ventana y de su Header según la pantalla
    └── VoterAvatars         fotitos de votantes (compartido por las vistas de votación)

StarterGui                   (src/StarterGui: solo init.meta.json por GUI)
├── HUD                      siempre visible, DisplayOrder 0
├── Shop/Settings/Codes/DailyRewards/PlaytimeRewardsGui   ventanas, DisplayOrder 10
├── VotingMapGui             popup del servidor, DisplayOrder 20
├── SpectatorGui             controles del espectador, DisplayOrder 25
└── ShopPurchaseGui          efecto de compra, DisplayOrder 150
```

### Cómo arranca

- **Servidor:** `Main` hace `require` de `Remotes` (eso crea los remotes). Después
  requiere cada ModuleScript de `Services` cuyo nombre termine en `Service` (sin `_`
  al inicio) y llama a su `Init()` en un hilo propio.
- **Cliente:** `ClientMain` inicializa `UIManager` primero y en forma sincrónica.
  Después requiere los demás ModuleScripts de `Controllers` en orden alfabético (salvo
  los que empiezan con `_`) y llama a cada `Init()` en un hilo propio. Si un controller
  falla o se queda esperando su GUI, no frena a los demás.

---

## Qué hace cada archivo clave

### Cliente

| Archivo | Rol |
|---|---|
| `ClientMain.client.luau` | Carga automática de controllers (UIManager primero, ignora `_*`). |
| `Controllers/UIManager.luau` | `Register`, `Open`, `Close`, `Toggle`, `CloseAll`, `IsOpen`, `GetOpen`, `WaitForGui`. Una sola ventana a la vez; anima con `UIEffects.popIn/popOut`. Señales `Opened`/`Closed` y helpers `OnOpened(name, fn)`/`OnClosed(name, fn)`. Si el `Main` tiene un `CloseButton`, lo conecta solo. Opción `CloseOnButtonB` para cerrar con el B del mando. |
| `Controllers/ShopController.luau` | Tienda (`ShopGui`, ventana "Shop"): una tarjeta `UITemplates.ShopCard` por item de `ShopConfig.Rows`. Compra por `RequestShopPurchase` (solo el Id); VIEW → `UIManager.Open(item.ViewTarget)`. |
| `Controllers/HUDController.luau` | Tabla `BUTTONS = { ShopButton = "Shop", ... }` que mapea botones del HUD a `UIManager.Toggle`. |
| `Controllers/VotingMapController.luau` | Panel de votación de mapa (popup del servidor, no se registra en UIManager). Incluye el mock local de debug. |
| `Controllers/TopbarController.luau` | Íconos del topbar. Hoy: dos íconos de debug (solo Studio) para la votación real y la simulada. |
| `Controllers/NPCZoneController.luau` | Pisar el aro de un NPC abre la ventana `Gui` de su Config vía `UIManager.Open`. |
| `Controllers/NPCLookController.luau` | Los NPCs giran a mirar al jugador local. |
| `Controllers/SimulatorCircleController.luau` | Lasers (Beams) que suben y bajan en el borde de cada aro de `Workspace.SimulatorCircles`. Ajustes en `SimulatorCircleConfig` o por Attribute en cada aro. |
| `Controllers/_TemplateController.luau` | Plantilla comentada para una GUI nueva. |
| `Utils/UIEffects.luau` | `popIn`, `popOut`, `popButton`, `bindButton` (click + pop + callback), `bindHover`, `makeBlur` (blur de ventana), sonidos, `findChild`. |
| `Utils/UITemplates.luau` | `UITemplates.get(name)` / `UITemplates.clone(name)`. |
| `Utils/Signal.luau` | Señal ligera (`Connect`, `Once`, `Fire`, `Disconnect`). |

### Compartido

| Archivo | Rol |
|---|---|
| `Shared/Remotes/init.luau` | Lista declarativa de remotes. Expone `event(name)` y `func(name)`; `onServerEvent`/`onServerInvoke` con **cooldown por jugador**; y el bus `UpdateUI` con `fireAll`/`fireTo` (servidor) y `onUpdate` (cliente). |
| `Shared/ShopConfig.luau` | Catálogo de la tienda: `Items` (Product / GamePass / View), `Rows` (filas y proporciones), íconos y colores de botones. |
| `Shared/*Config.luau` | Datos y ajustes (data-driven). |

### Servidor

| Archivo | Rol |
|---|---|
| `Main.server.luau` | Arranque del servidor (Remotes → Services). |
| `Services/MapVote/MapVoteService.luau` | Autoridad de la votación: valida cada voto y aplica rate limit. `runVoteWindow(duration)` corre una ventana completa. |
| `Services/Loading/AssetManifestService.luau` | Publica los asset IDs de ServerStorage para la pantalla de carga. |
| `Services/Loading/LoadingService.luau` | Marca al jugador con el atributo `LoadingComplete` cuando aprieta PLAY/SKIP (`LoadingService.IsLoaded`). |
| `Services/Spectator/SpectatorService.luau` | Espectador y reportes. El webhook de Discord sale del secreto `DiscordReportWebhook` (Secrets de Roblox), nunca del código. |
| `Services/Shop/ShopService.luau` | Autoridad de la tienda: prompts, `ProcessReceipt` (otorga primero vía `RegisterGrant`, después confirma) y Game Passes (`OwnsPass`). |
| `Services/Npc/*` | Idle y cartel de los NPCs. |

---

## Reglas del proyecto

1. **Las ScreenGuis son solo visuales:** `ResetOnSpawn = false`, un Frame `Main` con
   `Visible = false` y ningún script adentro.
2. Nunca usar StarterCharacterScripts para lógica de UI.
3. **El servidor manda.** Toda compra o cambio de datos se valida y ejecuta en el
   servidor. El cliente solo pide por Remotes, mandando IDs (nunca precios ni
   cantidades), y el servidor valida tipo, rango y existencia.
4. **Data-driven:** los elementos repetidos se clonan desde `UITemplates` recorriendo
   un Config. Agregar un item = editar solo el Config.
5. **Scale, no Offset.** Probar siempre en el emulador de celular de Studio.
6. `pcall` en todo MarketplaceService, DataStore, thumbnails y otras APIs web.
7. Comentarios en español, con la ubicación en Studio en la primera línea del archivo.
8. Luau moderno: `for _, x in t do`, `if … then … else` como expresión, `task.*`, `:Once`.
9. **No poner un `UIScale` propio** en el `Main` de una ventana ni en botones que usan
   `bindButton`: UIEffects usa el suyo y Roblox aplica uno solo por objeto.

---

## Checklist: crear una GUI nueva (ej. "Inventory")

**En Studio (lo visual):**

- [ ] `StarterGui > InventoryGui` (ScreenGui): `ResetOnSpawn = false`, `DisplayOrder = 10`
      (o 20 si es popup/notificación).
- [ ] Adentro, un Frame `Main` con `Visible = false`, todo en **Scale**
      (usá `UIAspectRatioConstraint` para que no se deforme).
- [ ] Opcional: un botón `CloseButton` dentro de `Main` (UIManager lo conecta solo).
- [ ] Si hay filas o cards repetidas: diseñá una y movela a
      `ReplicatedStorage > UITemplates` (ej. `InventorySlot`).
- [ ] Si se abre desde el HUD: agregá `InventoryButton` al HUD.

**En código:**

- [ ] Copiá `Controllers/_TemplateController.luau` como `Controllers/InventoryController.luau`
      y cambiá `WINDOW_NAME`, `GUI_NAME` y `ROW_TEMPLATE`.
- [ ] Si muestra datos: creá `Shared/InventoryConfig.luau` y recorrelo en el controller.
- [ ] Si pide algo al servidor:
  - [ ] Declará el remote en `Shared/Remotes/init.luau` (lista `EVENTS` o `FUNCTIONS`).
  - [ ] Creá `Server/Services/Inventory/InventoryService.luau` con `Init()` y
        `Remotes.onServerEvent("Nombre", handler, cooldown)`. Validá **todo** lo que llega.
- [ ] Sumá `InventoryButton = "Inventory"` en `HUDController.BUTTONS` (o en
      `WINDOW_ICONS` de TopbarController, o en el `Gui` del NPCConfig de un NPC).
- [ ] Probá en Studio en PC y en el emulador de celular.

No hace falta tocar `ClientMain` ni `Main`: los módulos nuevos se cargan solos.

---

## Pendiente a futuro

- **Tienda:** registrar los grants (`ShopService.RegisterGrant("Cash", fn)`) desde el
  `DataService`, guardar los `PurchaseId` en el perfil (idempotencia real), cargar los
  `ProductId` en `ShopConfig`, flujo de regalos y ventana `Pass` para el VIEW.
- Los IDs de sonido son de la cuenta de UBG. Si alguno da error de permisos, hay que
  resubirlo.
