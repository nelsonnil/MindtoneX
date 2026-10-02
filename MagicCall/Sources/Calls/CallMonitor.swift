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
        reassertDelegate()
    }

    /// Vuelve a registrar el delegado en la cola principal (retención fuerte vía AppModel → CallMonitor).
    func reassertDelegate() {
        observer.setDelegate(self, queue: .main)
        dlog("[CXCall] observer delegate=main retained=\(self) calls=\(observer.calls.count) · \(describeCalls())")
    }

    var currentCalls: [CXCall] { observer.calls }

    func describeCalls() -> String {
        guard !observer.calls.isEmpty else { return "ninguna" }
        return observer.calls.map { call in
            let state: String
            if call.hasEnded { state = "ended" }
            else if call.hasConnected { state = call.isOnHold ? "hold" : "connected" }
            else { state = call.isOutgoing ? "outgoing" : "incoming" }
            return "\(call.uuid.uuidString.prefix(8)):\(state)"
        }.joined(separator: " ")
    }

    /// Llamadas entrantes que aún no han conectado ni terminado.
    func ringingIncomingCalls() -> [CXCall] {
        observer.calls.filter { !$0.isOutgoing && !$0.hasConnected && !$0.hasEnded }
    }

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
        dlog("[CXCall] delegate \(call.uuid.uuidString.prefix(8)) → \(event.rawValue)\(repeated ? " (repetido, sin callback)" : "") out=\(call.isOutgoing) conn=\(call.hasConnected) end=\(call.hasEnded) hold=\(call.isOnHold) app=\(appState) total=\(callObserver.calls.count) · \(describeCalls())")
        guard !repeated else { return }
        onEvent?(event, call)
    }
}
