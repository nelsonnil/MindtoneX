# MagicCall: prueba de concepto de "la canción elegida suena como tono"

App iOS de pruebas para el efecto: el espectador nombra una canción, llama de verdad desde su
teléfono al iPhone del mago y oye esa canción como si fuera el tono de llamada.

El proyecto trae **dos rutas reales** (las dos usan la llamada auténtica del espectador) y un plan B:

| Ruta | Qué hace | Estado |
|---|---|---|
| **1 · Tono real (iOS 26)** | Recorta el preview a menos de 30 s, lo guarda en Archivos y abre Compartir para pulsar **“Usar como tono”** (función oficial de iOS 26). Es el tono de verdad del sistema. | API pública. Hay que confirmar en el iPhone que la opción aparece al compartir desde esta app. |
| **2 · Banner + audio de la app** | Modo silencio activado, la app delante con un fondo neutro, el audio "en caliente" a volumen 0 y `prefersNoInterruptionsFromSystemAlerts = true`. Al detectar la llamada (`CXCallObserver`) sube el volumen de la canción mientras aparece el banner real. | API pública. Hay que confirmar en iOS 26 real. |
| Plan B · CallKit | Llamada entrante **simulada** con la interfaz nativa. No es la llamada del espectador. | Solo como respaldo. |

Además incluye experimentos con **APIs privadas** (ToneLibrary, AVSystemController,
TelephonyUtilities, CoreTelephony, notificaciones Darwin) detrás de interruptores, para saber
cuáles responden en iOS 26 **sin jailbreak**. El jailbreak queda descartado.

El informe completo de investigación está en [`docs/magic-call-research-report.md`](docs/magic-call-research-report.md).

> Nada de esto se ha probado aún en un iPhone real: el código se escribió y revisó en Linux
> (sin compilar contra el SDK de iOS). Es posible que la primera compilación dé algún error menor
> de tipos; si pasa, envíame el mensaje exacto de Xcode.

---

## 1. Requisitos

- Mac con **Xcode 26** (o 16.x; el proyecto apunta a iOS 17+).
- iPhone con **iOS 26** y cable o emparejado por Wi-Fi.
- Apple ID. Con cuenta **gratuita** basta para instalar desde Xcode (la app caduca a los 7 días).
  Para TestFlight o ad hoc hace falta el Apple Developer Program de pago.

## 2. Compilar e instalar desde Xcode (recomendado, con experimentos privados)

1. Clona el repositorio y abre **`MagicCall.xcodeproj`** con doble clic.
   - Tras editar código o `project.yml`, **regenera siempre** el proyecto: `xcodegen generate --spec project.yml` (el `.xcodeproj` no se mantiene a mano).
2. En el navegador del proyecto selecciona **MagicCall** (icono azul) → target **MagicCall** →
   pestaña **Signing & Capabilities**:
   - Marca **Automatically manage signing**.
   - **Team**: elige tu Apple ID (añádelo en Xcode › Settings › Accounts si no aparece).
   - **Bundle Identifier**: cámbialo por uno único, p. ej. `com.tunombre.tonos`.
   - Comprueba que aparece **Background Modes › Audio** (ya va en el Info.plist). No hacen falta más capacidades.
3. En el iPhone: **Ajustes › Privacidad y seguridad › Modo de desarrollador** → activar y reiniciar.
4. Conecta el iPhone, elígelo arriba como destino y deja el esquema **MagicCall**.
5. Pulsa **▶︎ Run (⌘R)**.
6. Con cuenta gratuita, la primera vez: **Ajustes › General › VPN y gestión de dispositivos** →
   confía en tu certificado de desarrollador. Vuelve a lanzar.

El esquema **MagicCall** usa la configuración *Debug* (y *Release* al archivar), las dos con
`MAGIC_PRIVATE_PROBES`, así que los experimentos privados están incluidos.

### TestFlight (sin experimentos privados)

Apple escanea todo binario que se sube a App Store Connect (también para TestFlight interno) y
rechaza las referencias a APIs privadas (error **ITMS-90338**). Por eso existe el esquema
**MagicCall-TestFlight**, que compila sin `MAGIC_PRIVATE_PROBES`:

1. Elige el esquema **MagicCall-TestFlight** y el destino **Any iOS Device (arm64)**.
2. **Product › Archive** → **Distribute App** → **TestFlight & App Store** → subir.
3. Las rutas 1 y 2 y el plan B funcionan igual; solo desaparecen los experimentos privados.

### Ad hoc (con experimentos privados, sin pasar por Apple)

Con cuenta de pago: registra el UDID del iPhone en developer.apple.com, archiva con el esquema
**MagicCall** y elige **Distribute App › Release Testing (Ad Hoc)**. El .ipa no se sube a
App Store Connect, así que no pasa el escaneo de APIs privadas.

## 3. Cómo se usa

**Preparación** (pantalla del mago):
1. Escribe "título artista" y busca. La app consulta iTunes (tienda de tu región → US → Deezer),
   descarga el preview a memoria y muestra los tiempos. Puedes elegir otra coincidencia o pulsar "Escuchar 3 s".
2. Elige la ruta:
   - **Ruta 1 (tono real):** pulsa *Crear tono real y abrir Compartir* → **Usar como tono**
     (si no aparece, mira en *Más*; o abre **Archivos › En mi iPhone › Tonos › Canciones**, mantén pulsado el
     archivo › Compartir › Usar como tono). **Desactiva el modo silencio.** Listo: el iPhone sonará con la canción.
   - **Ruta 2 (banner):** revisa la lista "Antes de actuar" y pulsa **Entrar en escena**.

**En escena** (lo que ve el espectador: solo el fondo):
- **Toque** en cualquier sitio = sonar / parar (disparo manual).
- La llamada real se detecta sola y dispara la canción (`CXCallObserver`), si está activado.
- **3 toques en la esquina superior izquierda** = abre/cierra el registro superpuesto.
- **Mantener dos dedos 1,5 s** = salir de escena.
- Opcional: **Ajustes › Accesibilidad › Tocar › Toque posterior › Doble toque → "Sonar canción"**
  (atajo que la app publica automáticamente) para disparar sin tocar la pantalla.

**Fondo**: en Ajustes de la app puedes poner una captura de tu pantalla de inicio. Con el banner
real encima parece que el iPhone estaba sin más en el escritorio. La barra de estado de la
captura se tapa con un desenfoque para que solo se vea la real.

**Registro**: todo (eventos de llamada con milisegundos, interrupciones de audio, estado del
reproductor a +0,3/1/2,5/5/9 s del disparo, resultados de las APIs privadas) se guarda en
`magic-call-log.txt`. Expórtalo desde *Registro de pruebas › Compartir*, o búscalo en
**Archivos › En mi iPhone › Tonos** (la carpeta de la app).

## 3b. Entrada de canción: Manual o Voz IA (build 7)

Arriba, en **Song**, eliges **Manual** (escribes la canción, como antes) o **AI Voice**.

**AI Voice**: al pulsar **Perform** la app escucha la conversación (solo se ve la pantalla negra).
1. En cuanto la IA oye la canción que eligió el **espectador** (ignora los ejemplos que dice el mago,
   sigue los "no, mejor…", mezcla español/inglés), la busca y la deja preparada.
2. Si en **5 s** (ajustable) no hay cambios, la canción queda **bloqueada** y el micrófono se apaga del todo.
   Si el espectador cambia, se prepara la nueva y el contador vuelve a empezar.
3. Si la llamada llega antes del bloqueo, suena la mejor candidata de ese momento.
4. Al salir de Perform se borra todo (texto, candidata, canción) para la siguiente actuación.

Todo queda en el **Registro** con la etiqueta `[VOICE]` (lo oído, cada cambio de candidata, el bloqueo).
En la pantalla de preparación, **Try it here → Start test** muestra en vivo lo que oye y lo que elige la IA.

**Ajustes de voz** (*AI Voice → Voice settings*, o *Advanced → AI Voice settings*): clave de OpenAI
(se guarda en el Llavero del iPhone), motor, modelos, idioma, segundos hasta bloquear, confianza mínima,
vibración al bloquear y **Test microphone**.

| Motor | Ventajas | Inconvenientes |
|---|---|---|
| **OpenAI** (por defecto): `gpt-live-transcribe` en streaming por WebSocket + `gpt-6-luna` con salida JSON `{title, artist, confidence, reasoning}` | El mejor con títulos en inglés dichos en español y con cambios de opinión | Necesita clave e internet; coste por minuto |
| **Apple on-device** (`SFSpeechRecognizer`) | Gratis, sin clave, funciona sin red para transcribir | Peor con títulos en inglés; sin clave, la elección es una regla simple (última respuesta corta) |

Con Apple + clave, Apple transcribe y la IA de OpenAI elige la canción.

Audio: mientras escucha, la sesión pasa a `playAndRecord` + altavoz (el modo silencio no la apaga,
igual que `.playback`). Al bloquear vuelve a `.playback`. iOS muestra un **punto naranja** mientras el
micrófono está encendido; desaparece al bloquear.

**Share Ringtone + Perform**: pantalla negra → (AI Voice escucha y bloquea, o usa la canción escrita) →
se apaga el micro → se abre **Compartir** solo → pulsas **Usar como tono** → un toque en la pantalla
negra te lleva a la pantalla de inicio (usa una llamada privada de iOS, se puede desactivar en
*Advanced › Tap black screen to go Home*; si falla, desliza hacia arriba). **Modo silencio desactivado.**
Si iOS muestra una confirmación o abre Ajustes tras "Usar como tono", el Registro lo apunta
(`[SHARE PERFORM] ⚠️ app left the foreground…`): simplemente ve a inicio.

## 4. Protocolo de prueba mínimo

Necesitas un segundo teléfono para llamar. Antes de cada bloque, en la app: *Registro › papelera*.

| # | Configuración | Qué observar |
|---|---|---|
| 1 | Ruta 1. Silencio OFF. iPhone **bloqueado** | ¿Suena la canción como tono? ¿Aparecía “Usar como tono” en Compartir de la app o solo en Archivos? |
| 2 | Ruta 1. Desbloqueado, Banner | Igual |
| 3 | Ruta 2 por defecto: Banner, desbloqueado, silencio ON, app en escena | ¿Sigue sonando la canción con el banner encima hasta contestar/colgar? |
| 4 | Como 3 pero *prefersNoInterruptions* OFF | ¿Se corta al aparecer el banner? (control) |
| 5 | Como 3 pero *Standby en caliente* OFF | ¿Arranca la canción si empieza después de que suene la llamada? |
| 6 | Como 3 pero Llamadas entrantes = **Pantalla completa** | ¿Se corta? |
| 7 | Como 3 pero iPhone **bloqueado** | ¿Qué UI sale y si se corta |
| 8 | Como 3 con *mixWithOthers* ON | ¿Cambia algo? |
| 9 | Como 3, disparo manual con un toque justo al marcar el espectador | Latencia percibida |
| 10 | Toque posterior → "Sonar canción" | ¿Aparece algún aviso de Atajos en pantalla? |
| 11 | Experimentos privados: *Ejecutar pruebas de solo lectura*, luego *Intentar cambiar el tono* y *volumen de timbre a 0* | Líneas `[PRIVADO]` del registro; mira también Ajustes › Sonidos |
| 12 | Plan B CallKit | ¿Qué texto muestra iOS bajo el nombre? ¿Suena la canción? |

## 5. Qué enviarme de vuelta

- [ ] Modelo de iPhone y versión exacta de iOS (salen en la primera línea del registro).
- [ ] Ruta 1: ¿apareció "Usar como tono" al compartir **desde la app**? ¿Y desde Archivos? ¿Cuántos toques/segundos te llevó? ¿Sonó la canción en la llamada real bloqueado y desbloqueado?
- [ ] Ruta 2: para cada fila 3–10, ¿la canción siguió sonando al aparecer el banner (sí/no/se cortó a los N s)? ¿Algún parpadeo o detalle visual raro?
- [ ] El archivo `magic-call-log.txt` de cada bloque (o pega el texto).
- [ ] Las líneas `[PRIVADO]` y si Ajustes › Sonidos › Tono cambió de verdad.
- [ ] Si puedes: una grabación de pantalla, y desde el Mac la app **Consola** filtrando por
  `MagicCall` o `sandbox` mientras ejecutas los experimentos privados (las líneas `deny` dicen qué bloquea).

## 6. Estructura

```
project.yml                 Especificación XcodeGen (el .xcodeproj se genera con ella)
MagicCall.xcodeproj         Proyecto listo para abrir
MagicCall/Resources         Info.plist, Assets
MagicCall/Sources/App       AppModel (orquestación), Prefs (interruptores), App
MagicCall/Sources/Audio     RingtoneAudioEngine (sesión + reproducción), RingtoneExporter (ruta 1)
MagicCall/Sources/Calls     CallMonitor (CXCallObserver)
MagicCall/Sources/Songs     PreviewService (iTunes → Deezer, caché, latencias)
MagicCall/Sources/UI        Preparación, escena, ajustes, registro
MagicCall/Sources/Voice     AI Voice: micrófono, transcripción (OpenAI/Apple), elección de canción, ajustes
MagicCall/Sources/Perform   Flujo Perform de Share Ringtone y textos "How it works"
MagicCall/Sources/Intents   App Intents para Toque posterior / botón de Acción
MagicCall/Sources/Experiments  APIs privadas, CallKit, volumen
docs/                       Informe de investigación
```

## 7. Licencias

Los previews de iTunes/Deezer son material promocional. Las condiciones de Apple exigen
reproducirlos en streaming, sin guardarlos, junto a un enlace a la tienda y con atribución. Esta app
es para uso personal y de pruebas. La caché en disco viene desactivada por defecto, pero la
**ruta 1 guarda un archivo**, y eso va más allá de esas condiciones. Más detalle en el informe.
