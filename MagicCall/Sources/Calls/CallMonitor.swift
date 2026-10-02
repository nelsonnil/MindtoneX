import CallKit
import QuartzCore
import UIKit

/// Observa llamadas del sistema (celulares y VoIP) con la API pública CXCallObserver.
/// Solo expone UUID y estado: nunca el número ni el nombre del llamante.
final class CallMonitor: NSObject, CXCallObserverDelegate {
    enum Event: String {
        case incoming = "ENTRANTE (sonando)"
        case outgoing = "SALIENTE"
        case connected = "CONECTADA"
        case onHold = "EN ESPERA"
        case ended = "TERMINADA"
    }

    private let observer = CXCallObserver()
    private var lastEvent: [UUID: Event] = [:]
    var onEvent: ((Event, CXCall) -> Void)?

    func start() {
        observer.setDelegate(self, queue: .main)
        dlog("CXCallObserver activo. Llamadas en curso: \(observer.calls.count)")
    }

    var currentCalls: [CXCall] { observer.calls }

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let event: Event
        if call.hasEnded {
            event = .ended
        } else if call.hasConnected {
            event = call.isOnHold ? .onHold : .connected
        } else {
            event = call.isOutgoing ? .outgoing : .incoming
        }
        let repeated = lastEvent[call.uuid] == event
        lastEvent[call.uuid] = event
        if event == .ended { lastEvent[call.uuid] = nil }

        let appState: String
        switch UIApplication.shared.applicationState {
        case .active: appState = "active"
        case .inactive: appState = "inactive"
        case .background: appState = "background"
        @unknown default: appState = "?"
        }
        dlog("📞 CXCall \(call.uuid.uuidString.prefix(8)) → \(event.rawValue)\(repeated ? " (repetido)" : "") outgoing=\(call.isOutgoing) connected=\(call.hasConnected) ended=\(call.hasEnded) hold=\(call.isOnHold) app=\(appState) llamadas=\(callObserver.calls.count)")
        guard !repeated else { return }
        onEvent?(event, call)
    }
}
