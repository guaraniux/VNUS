# VNUS

Biblioteca de interfaz de un solo archivo para scripts de Roblox ejecutados en
entornos compatibles. Incluye una ventana arrastrable que se recorta al área
visible, pestañas, controles con guardado automático de perfiles, notificaciones,
diseño adaptable para escritorio y móvil, y animaciones.

- **Versión:** 1.0
- **Autor:** Guaraniux
- **Archivo único:** `VNUS-UI.lua`

## Uso

```lua
local source = game:HttpGet("https://raw.githubusercontent.com/guaraniux/VNUS/main/VNUS-UI.lua")
local VNUS = loadstring(source)()

local window = VNUS:CreateWindow({
    Name = "Mi script 1.0",
    GuiName = "MiScript",
    ConfigId = "DUELOS",
    Width = 500,
    Height = 560,
})

local mainTab = window:CreateTab("Combate")
local toggle = mainTab:CreateToggle({
    Name = "ESP",
    CurrentValue = true,
    Callback = function(value)
        print("ESP:", value)
    end,
})

window:SelectTab(mainTab)
```

La biblioteca prefiere `PlayerGui` para el `ScreenGui`; no hace falta modificarlo.

## Inyección automática

Al crear una pestaña llamada **`Ajustes`** o **`Settings`**, la biblioteca añade
automáticamente la sección **Interfaz**:

- `Tecla para mostrar/ocultar la interfaz` (compartida por todas las interfaces
  de VNUS de la sesión)
- `Diseño de la interfaz` (`Automático` / `Escritorio` / `Móvil`)
- `Tamaño de la interfaz` (75 %–125 %)
- Una línea de estado con el tipo de entrada, el diseño resuelto, la resolución y la escala.

También crea una pestaña **`Configuración`** con perfiles, guardado y carga
automática. Para desactivarlo:

```lua
local window = VNUS:CreateWindow({
    Name = "Mi script",
    DisableBuiltInResponsiveUI = true,  -- no inyectar la sección Interfaz
    DisableBuiltInUIKeybind = true,     -- no inyectar el atajo de teclado
    DisableBuiltInConfigs = true,       -- no crear la pestaña Configuración
})
```

## Opciones de `CreateWindow`

| Opción | Por defecto | Descripción |
| --- | --- | --- |
| `Name` / `Title` | `VNUS` | Título de la ventana. |
| `GuiName` | `VNUS` | Nombre del `ScreenGui`. |
| `ConfigId` | `GuiName`, luego `Name` | Carpeta de perfiles. Separa los datos de un script de los de otro. |
| `Width` / `Height` | `480` / `540` | Tamaño inicial en píxeles (mínimo 320 × 320). |
| `Configs.Root` | `VNUS/Configs` | Raíz de las carpetas de configuración. |
| `Configs.DefaultProfile` | `default` | Perfil seleccionado al arrancar. |
| `Configs.AutoSave` | `true` | Guarda los cambios de cualquier control registrado. |
| `Configs.AutoLoad` | `true` | Restaura el perfil seleccionado en la siguiente ejecución. |
| `DisableBuiltInResponsiveUI` | `false` | No inyectar la sección Interfaz. |
| `DisableBuiltInUIKeybind` | `false` | No inyectar el atajo de teclado. |
| `DisableBuiltInConfigs` / `DisableConfigs` | `false` | No crear la pestaña de configuración. |

## Controles

Todos los métodos de pestaña devuelven un objeto con `Set(value)` y `Get()`.

| Método | Opciones |
| --- | --- |
| `CreateSection(name)` | |
| `CreateButton(data)` | `Name`, `Callback` |
| `CreateToggle(data)` | `Name`, `CurrentValue`, `Callback` |
| `CreateDropdown(data)` | `Name`, `Options`, `CurrentOption`, `MaxVisible`, `Callback` |
| `CreateSlider(data)` | `Name`, `Range`, `Increment`, `CurrentValue`, `Suffix`, `Callback` |
| `CreateInput(data)` | `Name`, `CurrentValue`, `PlaceholderText`, `RemoveTextAfterFocusLost`, `Callback` |
| `CreateKeybind(data)` | `Name`, `Callback` |
| `CreateLabel(text)` | |
| `CreateParagraph(data)` | `Title`, `Content`, `Height` |
| `CreateDivider()` | |

Opciones comunes: `ConfigKey` (clave estable en los perfiles; si no se define,
se usa `Flag`, luego `Name` y finalmente `Text`), `NoConfig = true` (el control no se guarda) y
`Flag`, que publica el valor actual en `VNUS.Flags[flag]` para leerlo desde el
código sin modificar la interfaz. Los desplegables añaden `Refresh(options)`.

## API de la ventana

```lua
window:CreateTab(name)
window:SelectTab(tab)
window:SetTitle(text)
window:Toggle()
window:SetVisible(state)
window:SetCloseCallback(callback)

window:SetToggleKey(key)      -- "K", "F1", Enum.KeyCode…
window:GetToggleKey()
window:SetLayoutMode("Auto")  -- "Auto" | "Desktop" | "Phone"
window:SetUIScalePercent(100)

window:Center()
window:ClampToViewport()
window:ApplyResponsiveLayout()
window:ClosePopup()
window:Destroy()
```

## API de la librería

```lua
VNUS:Notify({Title = "Aviso", Content = "Mensaje", Duration = 3})
VNUS:SetAccent(Color3.fromRGB(255, 45, 130))
```

`VNUS.Theme` expone la paleta; el acento predeterminado es rosa chicle
(`rgb(255, 45, 130)`).

## Archivos en disco

```
VNUS/Configs/_ui_layout.json              diseño y escala globales de la interfaz
VNUS/Configs/<ConfigId>/_meta.json        perfil seleccionado, AutoSave, AutoLoad
VNUS/Configs/<ConfigId>/<profile>.json     valores de los controles
```

Necesita `writefile`, `readfile`, `isfile` y `makefolder`. Si faltan, la
interfaz sigue funcionando y solo se desactiva la configuración persistente.

## Estado compartido

La tecla de mostrar/ocultar y las preferencias de interfaz son globales durante
la sesión:

```lua
local env = (getgenv and getgenv()) or _G
env.__VNUS_UI_SHARED_STATE      -- ToggleKeyName, UIScalePercent, LayoutMode
env.__VNUS_CONFIG_SHARED_STATE  -- Root, AutoSaveDefault, AutoLoadDefault
```

## Convenciones de nombres y texto

- Textos visibles y comentarios en español.
- Identificadores, tokens internos y claves de configuración en inglés, para que
  las comparaciones y los perfiles guardados no dependan del idioma.
- Los tokens de diseño (`Auto`, `Desktop`, `Phone`) no cambian aunque sus
  etiquetas estén en español; `SetLayoutMode` acepta ambas formas.
