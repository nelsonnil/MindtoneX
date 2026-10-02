import AVFoundation
import CallKit

/// RESPALDO, no el efecto principal: genera una llamada entrante *simulada* con la UI nativa de
/// CallKit. No es la llamada del espectador; úsalo solo si la ruta real falla en tu iPhone.
/// Diferencias visibles frente a una llamada celular: iOS muestra el nombre de la app
/// ("<App> Audio") y la llamada no viene del teléfono del espectador.
final class CallKitFallback: NSObject, CXProviderDelegate {
    static let shared = CallKitFallback()

    private var provider: CXProvider?
    private var pendingUUID: UUID?

    private func makeProvider() -> CXProvider {
        if let provider { return provider }
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "MagicCall"
        let config = CXProviderConfiguration(localizedName: appName)
        config.supportsVideo = false
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.phoneNumber, .generic]
        config.includesCallsInRecents = false
        // Sin ringtoneSound propio: suena el tono del sistema, que el modo silencio calla,
        // y la canción la pone RingtoneAudioEngine igual que en la ruta real.
        let p = CXProvider(configuration: config)
        p.setDelegate(self, queue: .main)
        provider = p
        return p
    }

    func scheduleIncoming(callerName: String, after delay: TimeInterval) {
        let p = makeProvider()
        let uuid = UUID()
        pendingUUID = uuid
        dlog("CallKit: llamada simulada de “\(callerName)” en \(Int(delay)) s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let update = CXCallUpdate()
            update.remoteHandle = CXHandle(type: .generic, value: callerName)
            update.localizedCallerName = callerName
            update.hasVideo = false
            update.supportsHolding = false
            update.supportsDTMF = false
            p.reportNewIncomingCall(with: uuid, update: update) { error in
                if let error {
                    dlog("✗ CallKit reportNewIncomingCall: \(error.localizedDescription)")
                } else {
                    dlog("CallKit: llamada simulada mostrada")
                }
            }
        }
    }

    func endPending() {
        guard let uuid = pendingUUID else { return }
        provider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
        pendingUUID = nil
    }

    func providerDidReset(_ provider: CXProvider) {
        dlog("CallKit: providerDidReset")
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        dlog("CallKit: contestada (simulada) → se cuelga en 1 s")
        action.fulfill()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.endPending() }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        dlog("CallKit: rechazada/colgada (simulada)")
        action.fulfill()
        pendingUUID = nil
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        dlog("CallKit: didActivate audioSession")
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        dlog("CallKit: didDeactivate audioSession")
    }
}
