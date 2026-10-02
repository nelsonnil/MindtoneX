import PhotosUI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage(Prefs.Key.noInterruptions) private var noInterruptions = true
    @AppStorage(Prefs.Key.mixWithOthers) private var mixWithOthers = false
    @AppStorage(Prefs.Key.hotStandby) private var hotStandby = true
    @AppStorage(Prefs.Key.clipSeconds) private var clipSeconds = 10.0
    @AppStorage(Prefs.Key.startOffset) private var startOffset = 0.0
    @AppStorage(Prefs.Key.loopClip) private var loopClip = true
    @AppStorage(Prefs.Key.stopOnAnswer) private var stopOnAnswer = true
    @AppStorage(Prefs.Key.forceMediaVolume) private var forceMediaVolume = false
    @AppStorage(Prefs.Key.mediaVolumeTarget) private var mediaVolumeTarget = 0.8
    @AppStorage(Prefs.Key.boostSystemVolumeOnTrigger) private var boostSystemVolumeOnTrigger = true

    @AppStorage(Prefs.Key.autoTrigger) private var autoTrigger = true
    @AppStorage(Prefs.Key.tapTrigger) private var tapTrigger = true
    @AppStorage(Prefs.Key.volumeButtonTrigger) private var volumeButtonTrigger = false

    @AppStorage(Prefs.Key.diskCache) private var diskCache = false
    @AppStorage(Prefs.Key.deezerFallback) private var deezerFallback = true
    @AppStorage(Prefs.Key.storeCountry) private var storeCountry = ""

    @AppStorage(Prefs.Key.background) private var background = StageBackground.black.rawValue
    @AppStorage(Prefs.Key.maskStatusBar) private var maskStatusBar = true
    @AppStorage(Prefs.Key.hideStatusBar) private var hideStatusBar = false
    @AppStorage(Prefs.Key.darkStatusBarText) private var darkStatusBarText = false

    @AppStorage(Prefs.Key.darwinSignals) private var darwinSignals = true
    @AppStorage(Prefs.Key.toneIdentifierToTry) private var toneIdentifier = "system:Radar"
    @AppStorage(Prefs.Key.callKitCallerName) private var callKitCallerName = "Ana"
    @AppStorage(Prefs.Key.callKitDelay) private var callKitDelay = 5.0

    @AppStorage(Prefs.Key.autoStageRingtone) private var autoStageRingtone = true
    @AppStorage(Prefs.Key.discreetRingtoneUI) private var discreetRingtoneUI = true
    @AppStorage(Prefs.Key.ringtoneUseQuickLook) private var ringtoneUseQuickLook = false
    @AppStorage(Prefs.Key.attemptRingerMaxOnStage) private var attemptRingerMaxOnStage = false

    @State private var photoItem: PhotosPickerItem?
    @State private var confirmToneChange = false

    var body: some View {
        Form {
            audioSection
            triggerSection
            songSection
            stageSection
            privateSection
            ringtoneSection
            callKitSection
        }
        .navigationTitle("Ajustes")
        .onChange(of: photoItem) { _, newItem in
            guard let photoItem = newItem else { return }
            Task {
                if let data = try? await photoItem.loadTransferable(type: Data.self) {
                    StageImageStore.save(data)
                    background = StageBackground.image.rawValue
                    dlog("Fondo de escena: imagen propia guardada (\(data.count / 1024) KB)")
                }
            }
        }
    }

    private var audioSection: some View {
        Section {
            Toggle("prefersNoInterruptionsFromSystemAlerts", isOn: $noInterruptions)
            Toggle("Standby en caliente (sonar a volumen 0 antes de la llamada)", isOn: $hotStandby)
            Toggle("Opción .mixWithOthers", isOn: $mixWithOthers)
            Toggle("Repetir el fragmento en bucle", isOn: $loopClip)
            Toggle("Parar al contestar", isOn: $stopOnAnswer)
            Stepper("Duración del fragmento: \(Int(clipSeconds)) s", value: $clipSeconds, in: 4...30, step: 1)
            Stepper("Empezar en el segundo \(Int(startOffset)) del preview", value: $startOffset, in: 0...25, step: 1)
            Toggle("Forzar volumen multimedia al armar (MPVolumeView)", isOn: $forceMediaVolume)
            if forceMediaVolume {
                Slider(value: $mediaVolumeTarget, in: 0.3...1) { Text("Volumen") }
            }
            Toggle("Ruta 2: subir volumen multimedia al máximo al sonar (llamada o toque)", isOn: $boostSystemVolumeOnTrigger)
        } header: {
            Text("Audio")
        } footer: {
            Text("Con «subir al máximo al sonar» activo, la app guarda tu volumen, lo pone al 100 % cuando empieza la canción y lo restaura al colgar. Usa el MPVolumeView oculto para intentar no mostrar el cartel de volumen. Los cambios de «forzar al armar» se aplican al volver a entrar en escena.")
        }
    }

    private var triggerSection: some View {
        Section {
            Toggle("Automático al detectar la llamada (CXCallObserver)", isOn: $autoTrigger)
            Toggle("Toque en pantalla = sonar/parar", isOn: $tapTrigger)
            Toggle("Botón de volumen = sonar/parar", isOn: $volumeButtonTrigger)
        } header: {
            Text("Disparo")
        } footer: {
            Text("También puedes asignar el atajo “Sonar canción” a Toque posterior (Accesibilidad › Tocar) o al botón de Acción.")
        }
    }

    private var songSection: some View {
        Section {
            Toggle("Deezer como respaldo", isOn: $deezerFallback)
            Toggle("Caché en disco (ver nota de licencia)", isOn: $diskCache)
            TextField("Tienda iTunes (vacío = región del iPhone, p. ej. ES, MX, US)", text: $storeCountry)
                .textInputAutocapitalization(.characters)
            Button("Borrar cachés") { Task { await model.previews.clearCaches() } }
        } header: {
            Text("Previews")
        }
    }

    private var stageSection: some View {
        Section {
            Picker("Fondo", selection: $background) {
                ForEach(StageBackground.allCases) { Text($0.label).tag($0.rawValue) }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Elegir imagen de fondo…", systemImage: "photo")
            }
            Toggle("Tapar la barra de estado de la imagen", isOn: $maskStatusBar)
            Toggle("Ocultar barra de estado", isOn: $hideStatusBar)
            Toggle("Texto oscuro en barra de estado", isOn: $darkStatusBarText)
        } header: {
            Text("Escena")
        } footer: {
            Text("Truco: haz una captura de tu pantalla de inicio y úsala de fondo. Con el banner real encima parece que el iPhone estaba simplemente en la pantalla de inicio. No ocultes la barra de estado: la real (hora, batería) es lo más creíble.")
        }
    }

    private var privateSection: some View {
        Section {
            if PrivateProbes.isCompiled {
                Toggle("Escuchar notificaciones Darwin al iniciar", isOn: $darwinSignals)
                Button("Ejecutar pruebas de solo lectura") { model.runReadOnlyProbes() }
                TextField("Identificador de tono a probar", text: $toneIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                privateWriteButtons
            } else {
                Text("Este build se compiló sin experimentos privados (configuración TestFlight).")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.probeResults) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(r.outcome.rawValue) · \(r.name)").font(.footnote.bold())
                    Text(r.detail).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        } header: {
            Text("Experimentos privados")
        } footer: {
            Text("Esperado: casi todo bloqueado por sandbox/entitlements. El resultado exacto en iOS 26 es justo lo que necesitamos saber. Todo queda en el registro.")
        }
    }

    @ViewBuilder
    private var privateWriteButtons: some View {
        #if MAGIC_PRIVATE_PROBES
        Button("Intentar cambiar el tono de llamada (ToneLibrary)") { confirmToneChange = true }
            .confirmationDialog("Intentará cambiar el tono por defecto del sistema. Si funciona, usa “Restaurar” después.",
                                isPresented: $confirmToneChange, titleVisibility: .visible) {
                Button("Intentar") { model.runToneSet() }
            }
        Button("Restaurar tono original") { model.runToneRestore() }
        Button("Intentar volumen de timbre a 0 (AVSystemController)") { model.runRingerVolume(0) }
        Button("Intentar volumen de timbre a 0,5") { model.runRingerVolume(0.5) }
        Button("Intentar timbre al máximo (Ruta 1 · experimental)") { model.runRingerVolumeMax() }
        #endif
    }

    private var ringtoneSection: some View {
        Section {
            Toggle("Preparar tono al buscar canción", isOn: $autoStageRingtone)
            Toggle("Pantalla negra antes de Compartir", isOn: $discreetRingtoneUI)
            Toggle("Usar Vista previa en lugar de Compartir directo", isOn: $ringtoneUseQuickLook)
            if PrivateProbes.isCompiled {
                Toggle("Al preparar tono: intentar subir volumen del timbre (privado)", isOn: $attemptRingerMaxOnStage)
            }
        } header: {
            Text("Ruta 1 · menos toques")
        } footer: {
            Text("Deja activado «Preparar tono al buscar». «Vista previa» puede ayudar si «Usar como tono» no sale en Compartir. El volumen del timbre no se puede subir de forma fiable desde la app: si el interruptor privado no hace nada, usa Ajustes › Sonidos y vibración › Tono y alertas › «Cambiar con botones» y sube con los botones laterales.")
        }
    }

    private var callKitSection: some View {
        Section {
            TextField("Nombre que mostrará", text: $callKitCallerName)
            Stepper("Retraso: \(Int(callKitDelay)) s", value: $callKitDelay, in: 2...30, step: 1)
            Button("Programar llamada simulada (y entrar en escena)") {
                model.scheduleCallKitFallback()
                model.arm()
            }
            .disabled(model.loadState != .ready)
        } header: {
            Text("Respaldo CallKit (NO es la llamada real)")
        } footer: {
            Text("Solo para comparar o como plan B. iOS muestra el nombre de la app en la llamada y no es la llamada del espectador.")
        }
    }
}
