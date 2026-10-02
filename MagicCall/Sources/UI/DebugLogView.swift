import SwiftUI

struct DebugLogView: View {
    @EnvironmentObject private var log: DebugLog

    var body: some View {
        LogList(entries: log.entries)
            .navigationTitle("Debug Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: log.fileURL) { Image(systemName: "square.and.arrow.up") }
                    Button { UIPasteboard.general.string = log.fullText } label: { Image(systemName: "doc.on.doc") }
                    Button(role: .destructive) { log.clear() } label: { Image(systemName: "trash") }
                }
            }
    }
}

/// Registro superpuesto en escena (3 toques en la esquina superior izquierda para abrir/cerrar).
struct DebugOverlay: View {
    @EnvironmentObject private var log: DebugLog
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.isAudible ? "● PLAYING" : "○ waiting")
                    .font(.caption.bold())
                    .foregroundStyle(model.isAudible ? .green : .secondary)
                Spacer()
                Button("Play") { model.trigger(source: "debug") }
                Button("Stop") { model.silence(reason: "debug") }
                Button("Exit") { model.disarm() }
                Button { model.showDebugOverlay = false } label: { Image(systemName: "xmark.circle.fill") }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .padding(8)
            LogList(entries: log.entries)
        }
        .background(.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.top, 60)
        .padding(.bottom, 30)
    }
}

private struct LogList: View {
    let entries: [DebugLog.Entry]

    var body: some View {
        ScrollViewReader { proxy in
            List(entries) { entry in
                Text(entry.text)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .listRowBackground(Color.clear)
                    .id(entry.id)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: entries.count) { _, _ in
                if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}
