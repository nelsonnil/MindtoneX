# Llamada real + canción elegida como tono en iOS 26: informe de investigación

Para: Nelson · Fecha: 2 oct 2026 · PoC: proyecto Xcode `MagicCall` (rama `cursor/magic-call-poc-0daa`)

## 0. Resumen

**Recomendación: probar en el iPhone dos rutas reales, en este orden, con la app de pruebas ya preparada.**

1. **Ruta 1 · Tono real con "Usar como tono" de iOS 26.** iOS 26 añadió a la hoja de Compartir
   la acción oficial *Usar como tono* para MP3/M4A de menos de 30 s, que además lo deja como tono
   por defecto. La app busca el preview, lo recorta a 28 s, lo guarda y abre Compartir. El mago
   da 1–3 toques fuera de la vista del espectador, quita el modo silencio y listo: la llamada
   real suena con **el tono de verdad del sistema**. Es la mejor ilusión posible: funciona
   bloqueado, en pantalla completa o en banner, y aunque el espectador coja el teléfono.
   No usa APIs privadas.
   *Duda principal:* si la acción aparece al compartir **desde una app de terceros** (AppleInsider
   cuenta que en la beta funcionaba desde Archivos y no desde Notas). Si no aparece, el mismo
   archivo está en **Archivos**, y desde allí la opción sí está documentada (son 2–3 toques más).
2. **Ruta 2 · Banner real + audio de la app (automática).** Modo silencio activado, la app delante con un
   fondo neutro (o una captura de tu pantalla de inicio), la sesión de audio `.playback` activa
   y sonando **a volumen 0 antes** de la llamada, y `setPrefersNoInterruptionsFromSystemAlerts(true)`.
   Al llegar la llamada real, `CXCallObserver` avisa y la app sube el volumen en ~50 ms mientras
   el **banner real** baja encima. Apple documenta que, con estilo Banner, esta preferencia evita
   interrumpir la sesión hasta que el usuario **acepta** la llamada. No requiere tocar nada,
   pero **solo vale con el iPhone desbloqueado, la app delante y "Llamadas entrantes: Banner"**.
3. **Plan B:** llamada simulada con CallKit (no es la del espectador) o la ruta 2 con disparo manual.

**APIs privadas (sin jailbreak):** cambiar el tono con ToneLibrary, bajar a 0 el volumen del timbre
con AVSystemController o leer llamadas con TelephonyUtilities/CoreTelephony casi seguro **no**
funciona sin entitlements de Apple. Nadie ha publicado que funcione sin jailbreak; el único
proyecto público (ToneManager) dice expresamente que no puede. La app los incluye como
experimentos con interruptor para confirmarlo en iOS 26. **No hacen falta** para la recomendación.

**Jailbreak:** descartado por petición tuya. Solo se menciona como excluido.

**Previews:** la iTunes Search API devuelve un AAC de 30 s (~1 MB). Lo medí desde esta VM:
búsqueda 140–300 ms y descarga 75–150 ms. En el iPhone con 4G/5G espera ~0,5–2 s en total. Una
vez en memoria, el disparo es instantáneo.

### Leyenda

| Marca | Significado |
|---|---|
| **[DOC]** | Comportamiento o API documentados por Apple |
| **[NODOC]** | No documentado o API privada (funciona sin jailbreak, pero sin garantías) |
| **[JB]** | Requiere jailbreak o entitlements imposibles: **excluido** |
| **[VERIF]** | Lo verifiqué yo (en esta VM o en fuentes primarias) |
| **[INF]** | Inferencia razonada; no verificada |
| **[iPhone]** | Solo se puede confirmar en un iPhone real; **yo no tengo uno**, depende de tus pruebas |

---

## 1. Qué hice y qué no pude hacer

- Investigué la documentación de Apple (AVAudioSession, CallKit, iTunes Search API), artículos
  de soporte de iOS 26 y fuentes técnicas públicas sobre ToneLibrary y otras APIs privadas.
- **Verifiqué desde la VM** la iTunes Search API (tiendas US/ES/MX, latencias, formato y duración
  del preview, cabeceras) y Deezer como respaldo.
- Escribí un **proyecto Xcode completo** (XcodeGen + `.xcodeproj` generado) con las dos rutas, el
  plan B, los experimentos privados con interruptores y un registro de pruebas exportable.
- **No pude compilar contra el SDK de iOS ni probar en un iPhone.** Solo comprobé la sintaxis con
  `swiftc -parse` y generé el proyecto. Todo lo que depende de cómo se comporta iOS 26 en un
  dispositivo real va marcado **[iPhone]**.

## 2. Respuestas a las preguntas de la sección 7

**P1. ¿Puede una app normal mantener su audio con el banner de una llamada celular real? ¿Con qué configuración?**
Sí, según Apple. `AVAudioSession.setPrefersNoInterruptionsFromSystemAlerts(true)` (iOS 14.5+)
existe justo para eso. La documentación dice que, con el estilo Banner, la sesión **no se
interrumpe** por la llamada entrante; solo se interrumpe si el usuario la acepta **[DOC][VERIF en la doc]**.
Configuración propuesta: categoría `.playback`, modo `.default`, sin opciones (y `.mixWithOthers`
como experimento), la preferencia activada **antes** de `setActive(true)`, y la sesión activa y
reproduciendo antes de la llamada. No encontré indicios de que iOS 26 haya cambiado esto **[INF]**.
Falta confirmarlo **[iPhone]**: es la fila 3 de la matriz.

**P2. ¿Qué cambia entre Banner y Pantalla completa?**
Con *Pantalla completa*, la preferencia **no tiene efecto** y el sistema interrumpe la sesión
**[DOC]**. Además, la interfaz de llamada tapa la app. La ruta 2 exige *Banner* (Ajustes › Apps ›
Teléfono › Llamadas entrantes). La ruta 1 no depende de este ajuste.

**P3. ¿Detecta bien CXCallObserver la llamada entrante con la app en primer plano? ¿Qué datos da y con qué timing?**
Sí, `CXCallObserver` es la API pública para llamadas celulares y VoIP **[DOC]**. `CXCall` expone
`uuid`, `isOutgoing`, `hasConnected`, `hasEnded` e `isOnHold`, **nunca el número ni el nombre** **[DOC]**.
Llamada entrante sonando = `!isOutgoing && !hasConnected && !hasEnded`. En primer plano los
eventos llegan de forma fiable; en segundo plano no, desde iOS 14 **[NODOC: informes de foros]**.
Llega varias veces por llamada, así que hay que quitar duplicados (la app lo hace). Timing:
debería llegar más o menos a la vez que el banner. Calculo decenas a pocos cientos de ms **[INF]**;
la app registra los milisegundos exactos **[iPhone]**.
Ojo con iOS 26: si *Filtrar llamadas de desconocidos* está en "Preguntar motivo", el sistema
contesta él mismo primero y la llamada te llega tarde y con otro aspecto. Ponlo en **Nunca** **[DOC]**.

**P4. ¿Puede la app arrancar la canción justo antes o justo al llegar la llamada sin que la interrumpan?**
Antes, sí: es lo que hace el *standby en caliente* (la sesión ya activa y sonando a volumen 0).
Arrancarla **después** de que empiece a sonar es más arriesgado: activar una sesión no mezclable
durante una llamada puede fallar con prioridad insuficiente (`'!pri'`) **[DOC: códigos de error de AVAudioSession; INF: que pase aquí]**.
Por eso el diseño solo **sube el volumen** al disparar. La app tiene el interruptor para comparar
las dos formas **[iPhone]** (filas 3 y 5).

**P5. ¿Hay alguna API que calle solo el tono normal y deje sonar el audio de la app?**
Sí, y es documentada: el **modo silencio**. Calla tonos, alertas y sonidos del sistema, y deja
sonar el audio multimedia de las apps con categoría `.playback` **[DOC]**. (`.ambient` y
`.soloAmbient` sí se callan; no las uses.) Detalles para que no se note:
- En iPhones con botón de Acción hay una opción en *Ajustes › Sonidos y vibraciones › Modo silencio*
  para mostrar u ocultar el icono en la barra de estado; desactívala **[DOC]**.
- La vibración en modo silencio se ajusta en *Sonidos y vibraciones › Vibración*. Una llamada que
  vibra resulta natural; decide tú **[DOC]**.
- Los Enfoques (No molestar) también callan el tono, pero ponen un icono y pueden cambiar cómo se
  presenta la llamada. Mejor el modo silencio **[DOC/INF]**.
- No hay API pública para bajar el volumen del timbre a 0. La privada (AVSystemController) va como experimento **[NODOC]**.

**P6. ¿Puede una API privada cambiar el tono por defecto o el de un contacto justo antes de la llamada?**
Las APIs existen: `TLToneManager` en ToneLibrary.framework (`currentToneIdentifierForAlertType:`,
`setCurrentToneIdentifier:forAlertType:`, `importTone:metadata:completionBlock:`) **[NODOC]**.
Pero todo lo publicado que funciona es jailbreak. El autor de ToneManager escribe que no hay forma
de dar a una app los entitlements necesarios sin jailbreak **[VERIF: fuente pública]**. Lo que
bloquea, según la arquitectura **[INF]**:
(a) el sandbox impide escribir en `/var/mobile/Media/iTunes_Control/Ringtones`;
(b) `cfprefsd` rechaza escribir en dominios de preferencias de otro proceso;
(c) los servicios del sistema comprueban entitlements privados de Apple que no se pueden firmar
con una cuenta de desarrollador.
El tono de un contacto (clave privada `callAlert` de `CNContact`) tiene además un problema de
fondo: el espectador no es un contacto tuyo **[INF]**. Lo que sí resuelve P6 sin APIs privadas es
**"Usar como tono" de iOS 26**: cambia el tono por defecto en segundos con un gesto del usuario
**[DOC][VERIF: MacRumors/AppleInsider]**.

**P7. ¿Sirve ToneLibrary.framework en iOS 26 para una app privada o de TestFlight? ¿Qué entitlement la bloquea?**
Para TestFlight, no: una referencia a esos selectores provoca el rechazo ITMS-90338 al subirla
**[VERIF: foros de Apple]**. Instalada desde Xcode o ad hoc puede **cargarse** (`dlopen`) y quizá
**leer**, pero lo normal es que la escritura no tenga efecto o la deniegue el sandbox **[INF]**.
No sé el nombre exacto del entitlement que falta. La app vuelca los métodos reales de iOS 26 e
intenta leer, cambiar y restaurar. Si conectas el iPhone al Mac y abres **Consola** filtrando
por `sandbox`/`MagicCall`, las líneas `deny` dirán qué lo bloquea **[iPhone]**.

**P8. ¿Hay APIs privadas de SpringBoard, Telephony, CoreTelephony o CallKit, o notificaciones Darwin, que mejoren la ilusión sin jailbreak?**
Nada que mejore la ilusión de forma clara:
- `CTTelephonyCenter` (CoreTelephony) y `TUCallCenter` (TelephonyUtilities) requieren
  entitlements de CommCenter o callservicesd. Sin ellos no llegan eventos o llegan vacíos **[NODOC/INF]**.
  La app los prueba de todos modos.
- `SpringBoardServices` está protegido por entitlements **[INF]**.
- Las notificaciones Darwin (`notify.h` es pública; los nombres no están documentados) dejan
  **leer** `com.apple.springboard.lockstate` y `ringerstate`. Valen para diagnosticar (¿está en
  silencio?, ¿bloqueado?), no para el efecto **[NODOC]**. Van en el registro.
- `CXCallObserver` (pública) ya da lo único útil: el momento en que llega la llamada.

**P9. ¿Pueden Atajos o App Intents cambiar el tono, el tono de un contacto o el estado de audio?**
El tono, no: Atajos no tiene esa acción. Sí tiene *Definir modo silencio* (solo en modelos con
botón de Acción), *Ajustar volumen* (multimedia) y *Definir Enfoque* **[DOC]**. Tampoco hay
automatización por "llamada entrante" **[INF: no existe en la lista de disparadores]**.
Para lo que sí sirven es para un **disparo físico oculto**: la app publica el atajo "Sonar
canción" (App Intent), que puedes asignar al **Toque posterior** (dos toques en la parte trasera)
o al botón de Acción. Falta confirmar si Atajos muestra algún aviso al ejecutarlo **[iPhone]**.

**P10. ¿Hay algún mecanismo más seguro (Enfoque, silencio, rutas, volumen, separar canal de alertas y multimedia)?**
Sí: separar canales con **modo silencio + `.playback`** es exactamente ese mecanismo, y es documentado.
Completa con: volumen multimedia alto (la app avisa si está por debajo de 0,5 y puede forzarlo
con MPVolumeView **[NODOC]**), Bluetooth desconectado (si no, el audio iría a los AirPods o al
coche; la app avisa) y ningún Enfoque activo.

**P11. ¿Bloqueado o desbloqueado? ¿Qué estado da la interfaz real más limpia?**
- Ruta 1 (tono real): **cualquiera**. Bloqueado da la pantalla de llamada clásica, perfecta.
- Ruta 2: **solo desbloqueado** con la app delante. Con el iPhone bloqueado, la llamada siempre
  sale a pantalla completa, sin importar el ajuste **[DOC: soporte/prensa]**. Lo esperable es que
  interrumpa el audio como el estilo pantalla completa **[INF][iPhone]** (fila 7).

**P12. ¿Puede salir el banner real con una pantalla propia debajo y sin transiciones sospechosas?**
Sí. El banner se superpone y la app sigue debajo; probablemente ni pasa a *inactive* **[INF]**
(la app registra `willResignActive` para comprobarlo **[iPhone]**). Para que no se note nada:
- **No cambies nada en pantalla al disparar.** El disparo solo cambia el audio.
- Pon de fondo una **captura de tu pantalla de inicio**. Se ve la barra de estado real (la de la
  captura se tapa) y se oculta el indicador de inicio (`persistentSystemOverlays(.hidden)`).
  Si el espectador mira, cree que estaba en el escritorio.
- Pantalla siempre encendida (`isIdleTimerDisabled`).
- Con la app delante, su audio no muestra nada en la Isla Dinámica **[INF]**.
- Riesgo: si el espectador toca un "icono" de la captura, no pasa nada. El mago sujeta el teléfono.

**P13. ¿Cuál es la forma más fiable de conseguir y reproducir 10 s de cualquier canción con poca latencia y sin interfaz?**
iTunes Search API → `previewUrl` → descarga completa a **memoria** (~1 MB) → `AVAudioPlayer(data:)`
→ `prepareToPlay` → standby a volumen 0 → al disparar, `currentTime = inicio` y fundido a 1 en
50 ms. Bucle de 10 s con micro-fundidos (un tono de verdad se repite). Sin interfaz:
`AVAudioPlayer` no muestra controles, y la app no publica *Now Playing* ni comandos remotos.
Detalle en §6.

## 3. Comparativa de enfoques

| Enfoque | Lo que ve/oye el espectador | Autenticidad | Fiabilidad del audio | Limpieza visual | Mago | Tipo |
|---|---|---|---|---|---|---|
| **R1. Llamada real + tono real con "Usar como tono" (iOS 26)** | Llamada iOS completamente normal, en cualquier estado | Total | Total (es el tono del sistema) | Perfecta | 1–3 toques ocultos + quitar silencio; restaurar el tono después | [DOC] |
| **R2. Llamada real + audio de la app + banner real** | Banner real sobre un fondo neutro o tu escritorio | Total | Documentado para Banner; falta confirmarlo en iOS 26 | Muy buena si está desbloqueado; imposible bloqueado o en pantalla completa | Nada (automático) o un toque | [DOC] |
| R3. Llamada real + simulación visual propia | Pantalla dibujada por la app + elementos reales | Total | La misma que R2 | Arriesgada: dibujar una llamada falsa *además* de la real duplicaría la interfaz | — | [DOC] |
| R4. CallKit auxiliar | Interfaz nativa de llamada, generada por la app | **No** es la llamada del espectador | Buena | Casi nativa, pero iOS añade el nombre de la app ("X Audio") | Programar con retraso | [DOC] |
| R5. Atajos / automatización | — | — | No cambia el tono | — | Sirve como **disparo** (Toque posterior) | [DOC] |
| R6. API privada ToneLibrary (cambiar el tono por defecto) | Llamada normal | Total | — | Perfecta | — | [NODOC]; casi seguro bloqueada → [JB] |
| R7. Volumen del timbre a 0 con API privada | Igual que R2, pero sin modo silencio | Total | Igual que R2 | Igual que R2 | — | [NODOC]; probablemente bloqueada |
| R8. Tono de contacto | — | — | — | — | El espectador no es contacto | No aplica |
| R9. Tono pre-creado (GarageBand o "Usar como tono" antes del show) | Llamada normal | Total | Total | Perfecta | Solo si **fuerzas** la canción | [DOC] |
| Jailbreak (tweaks de tonos o SpringBoard) | — | — | — | — | — | **Excluido** |

Sobre R3: con la ruta 2, la "simulación visual" útil se reduce a controlar el **fondo** bajo el
banner real. Dibujar una llamada falsa sería peor que usar el banner real.

## 4. Ranking razonado

1. **R1 · Tono real con "Usar como tono".** Gana en todos los criterios de la sección 9 salvo
   en sencillez para el mago: hay unos segundos de manipulación y abre Ajustes. Es documentada,
   aguanta TestFlight y App Store y no depende del estado del iPhone. Si la acción sale en el
   Compartir de la app, el mago la hace en ~3 s mientras el espectador busca el número.
   **Debe confirmarse [iPhone]:** que aparece desde la app (si no, desde Archivos), cuánto tarda
   en aplicarse y si al primer tono ya suena la canción.
2. **R2 · Banner + audio de la app.** Automática y sin manipulación visible. Depende de dos cosas:
   (a) que `prefersNoInterruptionsFromSystemAlerts` funcione en iOS 26 con llamadas celulares y
   (b) que el mago mantenga el iPhone desbloqueado, en Banner y en silencio. Las limitaciones están
   claras; el riesgo está en el sistema operativo.
3. **R4 · CallKit** como plan B si R1 y R2 fallan. La interfaz es nativa, pero la llamada no es la del espectador.
4. R5 como disparador complementario de R2.
5. R6/R7 solo como experimento informativo. Esperamos ✗.

**Combinación recomendada para actuar:** R1 cuando puedas manipular el teléfono unos segundos sin
que te vean. R2 cuando no puedas tocarlo, con el disparo automático más un toque de respaldo.

## 5. PoC mínimo (ya implementado en `MagicCall`)

1. Entrada de texto (sustituye a tu reconocimiento) → `PreviewService.search` → descarga a memoria.
2. **R1:** `RingtoneExporter.export` (AVAssetExportSession, AppleM4A, 28 s) → `UIActivityViewController`
   con el archivo → el mago elige *Usar como tono*. El archivo queda también en Archivos
   (`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`). Se registra qué actividad eligió.
3. **R2:** *Entrar en escena* → `configureSession()` → standby a volumen 0 → `CXCallObserver`
   detecta la entrante → `makeAudible()` → chequeos del reproductor a +0,3/1/2,5/5/9 s → se para
   al contestar o colgar.
4. Disparos: automático, toque, botón de volumen (opcional) y App Intent (Toque posterior).
5. Gestos ocultos: 3 toques en la esquina para el registro, 2 dedos 1,5 s para salir.
6. Registro con milisegundos, exportable. Plan B CallKit. Experimentos privados con interruptor.

Criterios de éxito para la ruta 2: en la fila 3 de la matriz, el chequeo `+2.5s` muestra
`isPlaying=true` con `t` avanzando y **no** aparece `INTERRUPCIÓN began` hasta contestar.
Para la ruta 1: la llamada real suena con la canción con el iPhone bloqueado.

## 6. Frameworks, clases y ajustes exactos

**Frameworks públicos:** AVFoundation/AVFAudio (`AVAudioSession`, `AVAudioPlayer`,
`AVAssetExportSession`, `AVURLAsset`), CallKit (`CXCallObserver`, `CXCall`, `CXProvider`,
`CXProviderConfiguration`, `CXCallUpdate`), MediaPlayer (`MPVolumeView`), AppIntents
(`AppIntent`, `AppShortcutsProvider`), UIKit (`UIActivityViewController`), SwiftUI, PhotosUI,
CryptoKit, Foundation (`URLSession`).

**AVAudioSession (ruta 2):**
```swift
let s = AVAudioSession.sharedInstance()
try s.setCategory(.playback, mode: .default, options: [])        // .mixWithOthers como experimento
try s.setPrefersNoInterruptionsFromSystemAlerts(true)            // iOS 14.5+; solo con Banner
try s.setActive(true)
// standby: player.volume = 0; player.play()  … al llegar la llamada: player.setVolume(1, fadeDuration: 0.05)
```
Observadores: `interruptionNotification` (tipo, `AVAudioSessionInterruptionReasonKey`,
`.shouldResume`), `routeChangeNotification`, `silenceSecondaryAudioHintNotification`,
`mediaServicesWereResetNotification` y KVO de `outputVolume`.

**CXCallObserver:**
```swift
observer.setDelegate(self, queue: .main)
func callObserver(_ o: CXCallObserver, callChanged c: CXCall) {
    if c.hasEnded { /* parar */ }
    else if c.hasConnected { /* contestada → parar */ }
    else if !c.isOutgoing { /* ENTRANTE sonando → disparar */ }
}
```

**Info.plist / capacidades:** `UIBackgroundModes = [audio]` (seguir sonando si la app pasa a
segundo plano), `UIFileSharingEnabled` y `LSSupportsOpeningDocumentsInPlace` (ruta 1 y registro
en Archivos). No hacen falta entitlements. CallKit no requiere capacidad para reportar una
llamada desde primer plano.

**Ajustes del iPhone (ruta 2):** Modo silencio ON (con su icono oculto en la barra si el modelo lo
permite) · Ajustes › Apps › Teléfono › Llamadas entrantes = **Banner** · Filtrar desconocidos =
**Nunca** · Sin Enfoque · Bluetooth desconectado · Volumen multimedia alto · Desbloqueado, con la
app delante · Bloqueo automático: la app lo impide mientras está en escena.

**Ajustes del iPhone (ruta 1):** Modo silencio **OFF** · Volumen del timbre alto · Filtrar
desconocidos = Nunca · Después: Ajustes › Sonidos y vibraciones › Tono → vuelve a tu tono y borra
el personalizado (desliza a la izquierda).

**APIs privadas probadas (solo en builds `MAGIC_PRIVATE_PROBES`):** `TLToneManager`
(`sharedToneManager`, `currentToneIdentifierForAlertType:`, `setCurrentToneIdentifier:forAlertType:`
y presencia de `import…`), `AVSystemController` (`getVolume:forCategory:`, `setVolumeTo:forCategory:`
con "Ringtone"), `TUCallCenter` (`sharedInstance`, `currentCalls`), `CTTelephonyCenterAddObserver`,
y `notify_register_dispatch` con `com.apple.springboard.{ringerstate,lockstate,hasBlankedScreen}`.
Todo por `dlopen`, `NSClassFromString` e IMP, con `@try/@catch` en Objective-C y registro
síncrono antes de cada llamada.

## 7. Implementación Swift

El código completo está en el proyecto. Las piezas clave:

| Archivo | Qué hace |
|---|---|
| `Sources/Audio/RingtoneAudioEngine.swift` | Sesión, standby en caliente, disparo con fundido, bucle del clip, instantáneas para el registro, decodificación de errores FourCC |
| `Sources/Calls/CallMonitor.swift` | `CXCallObserver`, clasificación de estados, quita duplicados |
| `Sources/Songs/PreviewService.swift` | iTunes (tienda local → US) → Deezer; ranking que penaliza karaoke/cover/live/remix; caché en memoria; caché de disco opcional; precalentado TLS |
| `Sources/Audio/RingtoneExporter.swift` | Ruta 1: recorte < 30 s y hoja de Compartir |
| `Sources/App/AppModel.swift` | Orquestación: armar/desarmar, disparos, interrupciones, chequeos +N s |
| `Sources/UI/StageView.swift` | Fondo de escena, gestos ocultos (UIKit, dos dedos reales), máscara de la barra de estado |
| `Sources/Intents/MagicIntents.swift` | "Sonar canción" / "Parar canción" para Toque posterior o el botón de Acción |
| `Sources/Experiments/*` | APIs privadas, CallKit, MPVolumeView |

**Latencia y caché:**
- Al arrancar, la app abre conexiones TLS con `itunes.apple.com`, `audio-ssl.itunes.apple.com` y
  `api.deezer.com` (HEAD), y así se ahorra el handshake en la búsqueda real.
- Al resolver la canción se descarga el preview entero a memoria. 1 MB es poco y elimina el riesgo
  de que el streaming se quede sin datos justo cuando suena la llamada.
- Caché en memoria por consulta y por URL. La caché de disco está **desactivada** por defecto (licencia, §10).
- Orden de respaldo: iTunes en la tienda de tu región → iTunes US → Deezer → *(no implementado)*
  MusicKit `MusicCatalogSearchRequest` → `Song.previewAssets` (requiere activar MusicKit en tu
  App ID de pago y el permiso del usuario; da los mismos previews que iTunes, así que solo aporta
  cobertura en algún caso raro).
- Spotify retiró `preview_url` para apps nuevas a finales de 2024 **[INF: anuncio público, no verificado aquí]**. No se usa.

**Mediciones desde esta VM [VERIF]** (centro de datos; en el iPhone será más lento):

| Operación | Resultado |
|---|---|
| Búsqueda iTunes (US/ES/MX; Queen, Fonsi, Ritchie Valens) | 141–293 ms |
| Lookup por ID | 118 ms |
| Descarga del preview (5 canciones) | 75–148 ms, 0,98–1,09 MB |
| Formato | `audio/x-m4p` declarado, en realidad AAC-LC en MP4, **30,02 s**; `cache-control: max-age≈334 días` |
| Búsqueda Deezer | ~240 ms; preview MP3 de 30 s. Ojo: la búsqueda avanzada `artist:"" track:""` devolvió 0 resultados; la simple funciona |
| Errores tipográficos ("bohemian rapsody") y canciones en español | Encontradas correctamente |
| 25 peticiones seguidas | Todas 200. El límite orientativo publicado es ~20/min **[NODOC]**; la caché lo evita en la práctica |

Las tiendas varían: en ES, "Despacito" devolvió primero "(Versión Pop)". El ranking y la lista de
alternativas en pantalla están para eso.

## 8. Matriz de pruebas en un iPhone real

Para cada fila: borra el registro, llama desde otro teléfono, deja sonar unos 10 s, cuelga
(o contesta en las filas marcadas) y exporta el registro. Usa los mismos ajustes del iPhone salvo
el que se cambia. **Yo no puedo ejecutar ninguna fila.**

| # | Ruta | Llamadas entrantes | Bloqueo | Silencio | Ajuste de la app | Resultado esperado [INF] | Qué mirar en el registro |
|---|---|---|---|---|---|---|---|
| 1 | R1 | Banner | Bloqueado | OFF | — | Suena la canción como tono | — (oído) |
| 2 | R1 | Banner | Desbloqueado | OFF | — | Igual | — |
| 3 | R1 | Pantalla completa | Desbloqueado | OFF | — | Igual | — |
| 4 | R1 | — | — | — | Compartir **desde la app** vs desde **Archivos** | ¿Sale "Usar como tono"? | `Compartir: actividad=` |
| 5 | R2 | Banner | Desbloqueado | ON | por defecto | La canción sigue hasta contestar o colgar | `DISPARO`, chequeos +2.5/+5 `isPlaying=true`, sin `INTERRUPCIÓN began` |
| 6 | R2 | Banner | Desbloqueado | ON | noInterruptions **OFF** | Se corta al sonar (control) | `INTERRUPCIÓN began` |
| 7 | R2 | Banner | Desbloqueado | ON | standby **OFF** | Puede fallar al arrancar | `play=false` / `'!pri'` |
| 8 | R2 | Banner | Desbloqueado | ON | mixWithOthers ON | Igual que la 5 | — |
| 9 | R2 | **Pantalla completa** | Desbloqueado | ON | por defecto | Se corta | `INTERRUPCIÓN began` |
| 10 | R2 | Banner | **Bloqueado** (pantalla apagada, app en escena) | ON | por defecto | Pantalla completa y se corta | `didEnterBackground`, `INTERRUPCIÓN` |
| 11 | R2 | Banner | Desbloqueado | **OFF** | por defecto | Suenan tono + canción (control) | — |
| 12 | R2 | Banner | Desbloqueado | ON con **Enfoque** en vez de silencio | por defecto | Puede variar | — |
| 13 | R2 | Banner | Desbloqueado | ON | contestar | Para al instante y el audio de la llamada va bien | `CONECTADA`, `Silencio [contestada]` |
| 14 | R2 | Banner | Desbloqueado | ON | auto OFF, **toque** al marcar | Latencia humana | `DISPARO [toque]` |
| 15 | R2 | Banner | Desbloqueado | ON | **Toque posterior** | ¿Aviso de Atajos? | `DISPARO [App Intent]` |
| 16 | R2 | Banner | Desbloqueado | ON | botón de volumen | ¿Se oculta el HUD? | `Volumen multimedia …` |
| 17 | R2 | Banner | Desbloqueado | ON | AirPods conectados | Sonaría en los AirPods | `⚠️ La salida NO es el altavoz` |
| 18 | R2 | Banner | Desbloqueado | ON | Filtrar desconocidos = Preguntar motivo | Llega tarde o con otro aspecto | Timing del `CXCall` |
| 19 | R2 | Banner | Desbloqueado | ON | Modo de bajo consumo | Igual que la 5 | — |
| 20 | Plan B | — | Desbloqueado | ON | CallKit simulada | Interfaz nativa + "app Audio" | `CallKit:` |
| 21 | Privadas | — | — | — | solo lectura → cambiar tono → volumen 0 → restaurar | ✗ casi todo | `[PRIVADO]`, Consola del Mac |
| 22 | Ambas | — | — | — | iPhone con Isla Dinámica vs con notch | ¿Cambia el banner? | Captura o vídeo |

Repite las filas 5 y 9 en cada actualización de iOS 26.x: es el punto que más puede cambiar.

## 9. Si la ruta preferida falla en el iPhone

- **R1 no aparece en el Compartir de la app** → usa Archivos (2–3 toques más). Si tampoco aparece
  desde Archivos, revisa en el registro que el clip dura menos de 30 s (la app lo deja en 28 s)
  y envíame la línea `Tono exportado`; mientras tanto, usa R2.
- **R2 se interrumpe incluso con Banner** → prueba `mixWithOthers` (fila 8). Si sigue: R2 con
  **disparo manual justo después** de que aparezca el banner (fila 7 con el toque), o R1.
- **CXCallObserver llega tarde** → disparo manual (toque o Toque posterior) cuando el espectador
  pulse "llamar". La canción empieza un instante antes que el banner, lo cual es natural.
- **Nada de lo anterior** → plan B CallKit. Es honesto avisar de que ya no es la llamada del
  espectador: es una ilusión de respaldo, no la principal.
- **Canción no encontrada o sin preview** → iTunes US → Deezer → elige otra coincidencia de la lista
  → como último recurso, un tono neutro y "forzar" otra canción.

## 10. Licencias y condiciones de los previews

- **iTunes Search API / Apple Promo Content [VERIF: condiciones de Apple]:** los previews solo
  pueden usarse para **promocionar** el contenido. Deben ir junto a un enlace o insignia a la
  tienda y con la atribución "provided courtesy of iTunes". Deben reproducirse **solo en
  streaming, sin descargarse, guardarse ni cachearse**, y no pueden usarse por su valor de
  entretenimiento independiente.
- **Consecuencia:** un efecto de magia es, literalmente, "valor de entretenimiento independiente".
  Para **uso personal o privado** el riesgo práctico es bajo, pero no es un uso permitido. La
  ruta 2 descarga a **memoria** (en la práctica es un búfer, pero estrictamente no es streaming);
  la ruta 1 **guarda un archivo** y lo instala como tono, y eso queda claramente fuera de las
  condiciones. Para una app pública en el App Store habría que usar licencias reales (comprar los
  tonos en la iTunes Store, o un catálogo licenciado).
- **Deezer:** condiciones de API similares (uso no comercial, atribución, no almacenar) **[INF: no revisadas en detalle]**.
- **Derechos de autor en una actuación:** reproducir fragmentos de música en un espectáculo público
  puede requerir licencia de comunicación pública (SGAE, ASCAP…), aparte de lo de Apple **[INF]**.
- **Privacidad:** la app nunca ve el número del espectador. `CXCallObserver` no lo expone.

## 11. Distribución

| Vía | Experimentos privados | Rutas 1/2/CallKit | Notas |
|---|---|---|---|
| Xcode directo (cuenta gratuita) | Sí | Sí | Caduca a los 7 días; máximo 3 apps |
| Xcode directo / desarrollo (cuenta de pago) | Sí | Sí | 1 año |
| Ad hoc (cuenta de pago, UDID registrado) | Sí | Sí | No pasa por App Store Connect, así que no hay escaneo |
| TestFlight interno o externo | **No** (ITMS-90338 al subir) | Sí | Usa el esquema `MagicCall-TestFlight`; el externo además pasa una revisión de beta |
| App Store | No | Rutas 1/2 técnicamente sí | Revisión 2.5.1, más las licencias de los previews |

## 12. Riesgos abiertos

- R1: que "Usar como tono" exija un archivo en Archivos y no acepte uno compartido por una app, o
  que tarde en aplicarse. Mitigación: la fila 4 y la vía Archivos.
- R2: que iOS 26 trate las llamadas celulares de otra forma que lo documentado para "system
  alerts" en Banner; que el banner de la Isla Dinámica cambie de aspecto o suene un *haptic*;
  posibles parpadeos al pasar a *inactive*.
- El código no se ha compilado con el SDK de iOS: puede haber errores menores de tipos al
  compilar la primera vez (están localizados, y te digo cómo corregirlos con el mensaje de Xcode).
- Las APIs privadas pueden cerrar la app en experimentos concretos aunque estén protegidas con
  `@try`: no se pueden atrapar los fallos de memoria. La última línea del registro dirá cuál.
