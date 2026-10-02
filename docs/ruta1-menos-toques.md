# Ruta 1: reducir toques visibles (informe honesto iOS 26)

## Lo que Apple **no** permite (apps normales, sin jailbreak)

| Idea | ¿Posible? |
|------|-----------|
| Pulsar «Usar como tono» **sin** que el usuario lo toque | **No** |
| Atajo de Shortcuts «Definir tono» | **No existe** esa acción |
| Mostrar **solo** «Usar como tono» en Compartir | **No** (`excludedActivityTypes` no oculta extensiones del sistema) |
| Llamar API privada al gestor de tonos | Casi seguro **bloqueado** (experimentos en Ajustes) |
| Cambiar tono desde App Intents / Back Tap sin Compartir | **No** documentado |

## Lo que **sí** funciona (lo que implementamos)

1. **Preparar el archivo en silencio** al buscar la canción (`Actuacion.m4a`, &lt;28 s).
2. **Un botón «Aplicar tono ahora»** que solo abre Compartir (sin volver a exportar).
3. **Compartir optimizado**: tipo MIME audio, metadatos, ocultar AirDrop/redes/correo/etc.
4. **Pantalla negra** «Un momento…» un instante antes de Compartir (opcional).
5. **Favoritos del menú Compartir** (configuración **una vez** en el iPhone): «Usar como tono» queda **arriba = 1 toque**.

## Configuración única en el iPhone (Nelson)

1. Busca una canción en Tonos → **Aplicar tono ahora**.
2. En Compartir: desliza la fila de iconos a la **izquierda** → **Más** → **Editar**.
3. Toca **⭐** junto a **Usar como tono** → **Listo**.

Apple guarda esto **por app** (Tonos). No hay que repetirlo cada día.

## Rutina mínima en el show

1. (Antes, lejos del público) Buscar canción → esperar ✓ verde → **Aplicar tono ahora** → **1 toque** «Usar como tono» → silencio OFF.
2. (Opcional) Mientras el espectador marca el número: ya tienes el tono puesto; no toques nada visible.
3. Tras el truco: **Ajustes › Sonidos › Tono** → tu tono habitual.

## Alternativa: Vista previa

En **Ajustes › Preparar tono al buscar** activa **Vista previa**. Abre Quick Look → icono Compartir arriba → «Usar como tono». A veces sale más claro; prueba una vez.

## Truco de timing

- Prepara el tono **antes** de que nombren la canción (otra pista) **o** justo cuando la nombran pero **antes** de que saquen el teléfono.
- El espectador solo ve la **llamada normal**; los toques de Compartir van **antes**.
