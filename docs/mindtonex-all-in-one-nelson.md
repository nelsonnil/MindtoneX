# MindtoneX — rama `cursor/mindtonex-all-in-one` (build 104)

Rama única de integración para Nelson (`com.nelson.tono`, `CURRENT_PROJECT_VERSION` **104**).

## Qué incluye

| Pieza | Origen |
|--------|--------|
| **Un solo modo Performance** | `cursor/single-performance-mode-ui` — captura de escenario obligatoria, sin selector Stage/Phone ni atajo Silent; auto-share opcional (Voice, Notes, API, **Card**) |
| **Entrada Card / OCR** | `cursor/card-ocr-song-input-a336` — escaneo con volumen, `CardSongSession`, cámara en Perform |
| **Word API (caller label) opcional** | `cursor/word-api-caller-label-optional-bf92` — toggle **OFF** = sin cambio de comportamiento; extensiones Call Directory + Live Caller Lookup |

## Home

Performance · Song input (Manual, Voice, Notes, API, Card) · Biblioteca · **Word API (caller label)** · Feedback.

## iPhone — Word API + Call Directory

1. En Home, tarjeta **Word API (caller label)** → activa **Caller label (incoming call banner)**.
2. Configura Inject / Elips / Custom (endpoint de **palabra**, distinto del API de canción).
3. **Ajustes → Teléfono → Bloqueo e identificación de llamadas → MindtoneX Caller Label** (extensión Call Directory).
4. Perform: con el toggle ON, la app consulta la word API en paralelo al input de canción; el cambio de palabra bloquea (3 vibraciones cortas) y el banner de llamada entrante muestra la etiqueta.

Con el toggle **OFF**, no hay polling Word API, ni sync Call Directory, ni recarga de extensiones.

## Compilar

Abre `MagicCall.xcodeproj` (o `xcodegen generate --spec project.yml` tras cambios en `project.yml`). Esquema **MagicCall** incluye app + extensiones.
