import SwiftUI

/// Pantalla del mago (nunca la ve el espectador).
struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var queryFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                songSection
                if !model.results.isEmpty { resultsSection }
                stageSection
                realRingtoneSection
                checklistSection
                Section("Herramientas") {
                    NavigationLink("Ajustes y experimentos") { SettingsView() }
                    NavigationLink("Registro de pruebas") { DebugLogView() }
                }
            }
            .navigationTitle("Preparación")
        }
    }

    private var songSection: some View {
        Section {
            HStack {
                TextField("Título y artista (p. ej. Bohemian Rhapsody Queen)", text: $model.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($queryFocused)
                    .onSubmit { Task { await model.search() } }
                Button {
                    queryFocused = false
                    Task { await model.search() }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .disabled(model.query.trimmingCharacters(in: .whitespaces).isEmpty || model.loadState == .searching)
            }
            statusRow
        } header: {
            Text("Canción")
        } footer: {
            Text("Sustituye al mecanismo de reconocimiento de tu app. La búsqueda descarga el preview a memoria para que el disparo sea instantáneo.")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch model.loadState {
        case .idle:
            Text("Escribe una canción para empezar.").foregroundStyle(.secondary)
        case .searching:
            Label("Buscando…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .downloading:
            Label("Descargando preview…", systemImage: "arrow.down.circle").foregroundStyle(.secondary)
        case .ready:
            if let track = model.selected {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(track.title) — \(track.artist)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(track.source.rawValue) · \(model.timings)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(model.isAudible ? "Sonando…" : "Escuchar 3 s") { model.audition() }
                    .disabled(model.isAudible)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var resultsSection: some View {
        Section("Otras coincidencias") {
            ForEach(model.results.prefix(6)) { track in
                Button {
                    Task { await model.select(track) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(track.title).foregroundStyle(.primary)
                            Text("\(track.artist) · \(track.source.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if track == model.selected {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
    }

    private var stageSection: some View {
        Section {
            Button {
                model.arm()
            } label: {
                Label("Entrar en escena", systemImage: "theatermasks.fill")
                    .frame(maxWidth: .infinity)
                    .font(.headline)
            }
            .disabled(model.loadState != .ready)
        } footer: {
            Text("En escena: toque = sonar/parar · 3 toques en la esquina superior izquierda = registro · mantener 2 dedos 1,5 s = salir.")
        }
    }

    private var realRingtoneSection: some View {
        Section {
            Button {
                Task { await model.prepareRealRingtone() }
            } label: {
                Label("Crear tono real y abrir Compartir", systemImage: "bell.badge")
            }
            .disabled(model.loadState != .ready)
            if let url = model.exportedRingtone {
                Text("Guardado en Archivos › En mi iPhone › Tonos › Canciones › \(url.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Ruta 1 · tono real (iOS 26)")
        } footer: {
            Text("En Compartir elige “Usar como tono” (quizá en “Más”). Si no aparece, ve a Archivos › En mi iPhone › Tonos › Canciones, mantén pulsado el archivo › Compartir › Usar como tono. Para esta ruta el modo silencio debe estar DESACTIVADO. Después, restaura tu tono en Ajustes › Sonidos.")
        }
    }

    private var checklistSection: some View {
        Section("Antes de actuar (ruta 2 · banner + audio de la app)") {
            ChecklistRow(text: "Modo silencio ACTIVADO (el tono real no debe sonar)")
            ChecklistRow(text: "Ajustes › Apps › Teléfono › Llamadas entrantes: Banner")
            ChecklistRow(text: "Ajustes › Apps › Teléfono › Filtrar desconocidos: Nunca")
            ChecklistRow(text: "Ningún Enfoque activo · Bluetooth desconectado")
            ChecklistRow(text: "Volumen multimedia alto · iPhone DESBLOQUEADO con esta app delante")
            ChecklistRow(text: "Vibración en modo silencio: a tu gusto (Ajustes › Sonidos y vibraciones)")
        }
    }
}

private struct ChecklistRow: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checklist").font(.footnote)
    }
}
