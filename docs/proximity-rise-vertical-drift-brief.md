# Brief: glitch «Proximity Drift vertical» (abajo → Dynamic Island)

Documento para handoff a otro agente IA. Alineado con **Carphone CALL** (`ProximityRippleRenderer` / **Proximity Drift**); la parte de imagen a pantalla completa aplica también a otra app.

---

## Objetivo

Replicar el efecto **Proximity Drift** (refracción Metal: lente de luz, onda que deforma la imagen, borde prismático, dim + whiteout al final), pero:

| Actual (`drift`) | Nuevo (`ascent` / «Proximity Rise») |
|------------------|-------------------------------------|
| Origen ~centro del contenido | Origen en la **parte más baja** de la pantalla |
| Trayectoria diagonal hacia un lateral | **Línea recta vertical** hacia arriba |
| Destino lateral | Destino bajo **Dynamic Island** (centro horizontal, ~5–8 % desde arriba) |

La imagen de fondo **ocupa todo el viewport** (`aspect fill` o `bounds` completos), no solo el teclado del dialer.

---

## Referencia en repo (Carphone CALL)

- Motor Metal + coreografía: `CarphoneCALL/Sources/Engine/ProximityRipple.swift`
- Integración glitch: `CarphoneCALL/Sources/Engine/ProceduralGlitch.swift` → `buildRefraction(_:)` → `ProximityRippleRenderer`
- Variante actual diagonal: `Variant.drift` en `frame(at:)` (~líneas 143–152)
- Duración familia refraction: `GlitchTiming.refractionDuration` = **6.0 s**
- Posición «Dynamic Island» en CA (Proximity Waves): `y: height * 0.05`, `x: width * 0.5` en `buildProximity()`

**No reescribir el shader** salvo bug: el desplazamiento es radial desde `u.center`; mover el centro en vertical reproduce el drift en eje Y.

---

## Arquitectura (reutilizar)

1. `CAMetalLayer` a pantalla completa + textura del snapshot/imagen.
2. Capa `driver` (opacity 0→1) como reloj de timeline (igual que ahora).
3. `CADisplayLink` → `render(time: progress * duration)`.
4. Uniforms: mismo struct y mismo `ripple_fragment`.

### Imagen a pantalla completa (otra app o overlay full-screen)

En Carphone, el dialer usa `dialContentFrame` (bottom-aligned). Para **pantalla completa**:

```swift
let dialFrame = bounds  // imagen ya en aspect fill del bounds
// textura = captura o UIImage a CGImage del mismo aspecto que bounds
```

Si la imagen es más ancha que la pantalla, usar el mismo criterio que `dialContentFrame` pero **anclada abajo** solo si el diseño lo pide; si el usuario quiere «toda la pantalla», lo habitual es `dialFrame = bounds` y textura generada con `resizeAspectFill` en el tamaño del bounds.

---

## Nueva variante Metal: `ascent`

### 1) Enum en `ProximityRippleRenderer.Variant`

```swift
enum Variant {
    case ripple, pulse, drift, halo
    /// Lente nace abajo del todo y sube en vertical hacia Dynamic Island.
    case ascent

    init?(_ video: VideoName) {
        switch video {
        // ...
        case .realisticRippleAscent: self = .ascent
        default: return nil
        }
    }
}
```

### 2) Coreografía en `frame(at t:)` — copiar `drift` y sustituir solo `center` + timing

Coordenadas **normalizadas** (como el resto): `center.x`, `center.y` ∈ [0,1] respecto a `width`/`height`.

```swift
case .ascent:
    // X fijo: centro horizontal (Dynamic Island)
    f.center = CGPoint(
        x: 0.5,
        y: k(t, [(0, 1.06), (0.2, 1.06), (3.6, 0.06), (5.9, 0.06)], true)
    )
    // Radio y amplitud: misma “lente” que drift, ajustada al viaje más largo en Y
    f.radius.x = k(t, [(0.15, 0), (0.8, 0.22), (2.8, 0.38), (3.6, 0.42)], true)
    f.amp.x = k(t, [(0.15, 0), (0.9, 16), (3.2, 18), (4.0, 0)], true)
    f.trail = f.amp.x * 0.6
    f.rim = k(t, [(0.15, 0), (0.7, 1), (3.4, 1), (4.0, 0)], true)
    f.glow = k(t, [(0.3, 0), (1.2, 0.75), (3.4, 0.85), (4.0, 0)], true)
    f.dim = k(t, [(0, 0), (0.9, dimPeak), (4.2, dimPeak), (5.8, 0)], true)
    f.whiteout = k(t, [(3.5, 0), (4.2, 0.9), (5.9, 0)], true)
    f.hue = t * 0.35
```

**Notas de diseño**

- `y: 1.06` al inicio: el frente de onda **entra desde debajo** del borde inferior (equivalente a «aparece en la parte más baja»).
- `y: 0.06` al final: alineado con earpiece / Dynamic Island (misma referencia que `height * 0.05` en Proximity Waves).
- **Línea recta**: `center.x` siempre `0.5`; solo animar `center.y`. No usar keys laterales como en `drift` (`1.25`, `0.32`).
- Interpolación `smooth: true` en Y mantiene suavidad; si Nelson quiere subida **constante**, usar `smooth: false` entre `(0.2, 1.06)` y `(3.6, 0.06)`.

### 3) Dynamic Island / safe area (dispositivos reales)

Opcional pero recomendable en iOS:

```swift
private var dynamicIslandNormalizedY: CGFloat {
    let topInset = view.safeAreaInsets.top  // ~59 pt en iPhone con DI
    guard bounds.height > 0 else { return 0.06 }
    return (topInset * 0.5) / bounds.height  // punto bajo la isla, no el borde del notch
}
```

Usar ese valor en lugar de `0.06` fijo en la última keyframe de `center.y`.

---

## Registro en Carphone (si es un estilo más en la galería)

| Archivo | Cambio |
|---------|--------|
| `CarphoneCALL/Sources/Support/Types.swift` | `case realisticRippleAscent = "realistic_ripple_ascent"`; añadir a `videoName`, `glitchFamily` → `.refraction`, `glitchAudioStem` → `"glitch_ripple_drift"` (reutilizar audio drift) o nuevo stem, `stillMoment` ~`0.36`, `title` → `"Proximity Rise"` |
| `CarphoneCALL/Sources/Engine/ProceduralGlitch.swift` | En `GlitchScene.build`, incluir `.realisticRippleAscent` en el `case` de `buildRefraction` |
| `CarphoneCALL/Sources/UI/GlitchGallery.swift` | Icono SF Symbol sugerido: `arrow.up.circle` o `waveform.path` |
| `Resources/Glitch/` | Opcional: copiar `glitch_ripple_drift_{dark,light}.m4a` como placeholder |

Raw value **no cambiar** una vez publicado (settings / URL scheme).

---

## Vista mínima reutilizable (otra app, SwiftUI)

```swift
struct FullScreenRippleGlitch: UIViewRepresentable {
    let image: UIImage
    var duration: TimeInterval = 6
    var onComplete: () -> Void = {}

    func makeUIView(context: Context) -> ProceduralGlitchView {
        let v = ProceduralGlitchView(
            style: .realisticRippleAscent,  // o pasar variant internamente
            content: image,
            duration: duration,
            mode: .once
        )
        return v
    }

    func updateUIView(_ uiView: ProceduralGlitchView, context: Context) {}

    static func dismantleUIView(_ uiView: ProceduralGlitchView, coordinator: ()) {
        uiView.stop()
    }
}

// En onAppear del contenedor full-screen:
// glitchView.start(from: CACurrentMediaTime(), playbackRate: 1.0) { onComplete() }
```

Si la otra app **no** tiene `ProceduralGlitchView`, extraer solo `ProximityRippleRenderer` + un `UIView` contenedor con `layoutSubviews` → actualizar `layer.frame` / `drawableSize` y el `DisplayLink` (copiar de `ProceduralGlitchView.startRefraction`).

---

## Criterios de aceptación (QA visual)

1. Con imagen estática a pantalla completa, a ~0.5 s se ve una **lente brillante** entrando por el borde inferior.
2. La deformación (squash/stretch del contenido) **sube en vertical** sin desviarse lateralmente.
3. El pico de luz / borde prismático **termina centrado bajo Dynamic Island**, no en el centro geométrico de la pantalla.
4. Entre ~3.5–4.2 s hay flash de **whiteout** breve; a 5.9–6.0 s imagen **limpia** (sin dim residual).
5. Galería: thumbnail en `stillMoment`; preview loop respeta `GlitchTiming.refractionDuration` y speed slider.
6. Fallback: si Metal falla, no crashear (en Carphone ya cae a `buildProximity()` — valorar un fallback CA vertical o pantalla negra + fade).

---

## Qué **no** hacer

- No animar `center.x` (rompe la «línea recta»).
- No reutilizar keys de `.drift` sin cambiar Y (seguiría yendo al lateral).
- No acortar duración por debajo de 6 s en Carphone sin actualizar `GlitchTiming` y audio.
- No cambiar raw values de estilos existentes.

---

## Resumen para el agente implementador

**Tarea:** Añadir variante `.ascent` en `ProximityRippleRenderer` con trayectoria `(0.5, 1.06) → (0.5, ~0.06)`, reutilizando shader y pipeline de Drift; registrar `realisticRippleAscent` en el enum de glitches; asegurar que el contenido sea **full-screen** cuando la fuente sea una imagen a pantalla completa (`dialFrame = bounds`). Ajustar `dynamicIslandNormalizedY` con `safeAreaInsets.top` si el host view tiene safe area válida.
