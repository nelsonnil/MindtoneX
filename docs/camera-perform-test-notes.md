# Camera Perform — notas para testers

## Antes del show

1. **OpenAI (recomendado):** Song input → **Voice** → pestaña **Test** → pega tu API key. Sin clave, Perform usa OCR local (peor con letra a mano).
2. **Cámara:** Ajustes → MindtoneX → **Cámara** → permitir.
3. **Iluminación:** Carta legible, sin sombras fuertes; mantén el teléfono quieto un instante antes de escanear.
4. **Volumen:** En Perform con Camera, el volumen de medios baja ~50% para que **subir volumen** dispare el escaneo (no play/pause).

## Durante Perform (Song = Camera)

1. Entra en Perform con la carta visible para la cámara trasera.
2. Pulsa **subir volumen** una vez → el log debe mostrar `snapshot + OpenAI` si hay API key, o `OpenAI skipped (no API key…)` + `local OCR`.
3. Segunda pulsación de volumen (si hay candidato de canción) confirma el lock.

## Leer el log de Perform

| Mensaje | Significado |
|--------|-------------|
| `L1 «—» · L2 «—» · L3 «—»` | Cero texto reconocido en las tres líneas. |
| `Vision saw 0 text regions` | Frame OK pero Vision no ve texto (luz/foco/tamaño). |
| `blank frame` | No llegaron píxeles de cámara. |
| `camera not running` | Sin frame de vídeo; repite volumen arriba. |
| `song search skipped — no line-1 text` | Canción no buscable sin línea 1; prueba OpenAI + mejor luz. |
| `App Group not signed` | Solo afecta **Caller name** vía Call Directory; **song/camera siguen**. Provisioning: `group.com.nelson.tono` en app + extensión. |
| `Enable MindtoneX under Settings → Phone…` | Opcional para Call Directory; no bloquea OCR/canción. |

**Caller name** y **song** son independientes: L2/L3 vacíos no impiden búsqueda de canción si L1 tiene texto.
