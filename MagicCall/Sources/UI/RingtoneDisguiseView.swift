import SwiftUI

/// Pantalla negra breve mientras se exporta el tono, para que no se vea la lista de Preparación.
struct RingtoneDisguiseView: View {
    var body: some View {
        Color.black
            .ignoresSafeArea()
            .overlay {
                Text("One moment…")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.35))
            }
    }
}
