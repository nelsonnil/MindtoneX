# Word API — tarjeta contacto (dos modos)

## Tarjeta (home Word API)

- **Toggle maestro:** guardar la palabra bloqueada como nombre de **Contactos** (en segundo plano, sin UI de Contactos al bloquear).
- **Modo Desconocido:** al pulsar **Perform** (con toggle ON + caller label ON) → hoja de marcado → llamada `tel:` → al colgar la **saliente** (`CallMonitor` `.ended` + outgoing) se guarda E.164 → continúa arm/stage (Voice + poll Word).
- **Modo Conocido:** elegir contacto (`CNContactPickerViewController`) → guardar id + teléfono; Perform **sin marcado**; al bloquear palabra → **renombrar** `givenName` del contacto elegido.
- **Restaurar nombre (Conocido):** toggle en tarjeta; al cerrar **Word API connection** (`onDisappear` del sheet) revierte `givenName` al guardado al elegir contacto (solo si hubo rename en lock).

## Lock

`WordApiSession` → `SpectatorWordContactService.applyOnWordLock` cuando contact toggle ON.

Permiso denegado → `PerformUserLog` + Call Directory fallback.
