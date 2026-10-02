import Foundation
import UIKit

/// Experimentos con APIs privadas / no documentadas (sin jailbreak).
///
/// - Solo se compilan con MAGIC_PRIVATE_PROBES (configs Debug/Release; NO en TestFlight).
/// - Se invocan por reflexión (dlopen + NSClassFromString + IMP), nunca se enlazan.
/// - Cada llamada arriesgada se envuelve en MCObjC.performSafely y se registra con `sync: true`
///   ANTES de ejecutarse, para que si el proceso muere quede la última línea en el log.
/// - Los nombres de selectores vienen de class-dumps públicos de iOS 11–17. NO están
///   verificados en iOS 26: por eso cada experimento vuelca primero los métodos que existen
///   de verdad. Un "no existe el selector" significa "hay que mirar el volcado", no "bloqueado".
enum PrivateProbes {
    struct Result: Identifiable {
        let id = UUID()
        let name: String
        let outcome: Outcome
        let detail: String
    }

    enum Outcome: String {
        case worked = "✓ funcionó"
        case readOnly = "◐ solo lectura"
        case missing = "? selector/clase no encontrado"
        case blocked = "✗ bloqueado/sin efecto"
        case notCompiled = "— no compilado"
    }

    static var isCompiled: Bool {
        #if MAGIC_PRIVATE_PROBES
        return true
        #else
        return false
        #endif
    }

    static func record(_ r: Result) -> Result {
        dlog("[PRIVADO] \(r.name): \(r.outcome.rawValue) — \(r.detail)", sync: true)
        return r
    }

    #if MAGIC_PRIVATE_PROBES

    // MARK: Runtime helpers

    @discardableResult
    static func load(_ path: String) -> Bool {
        if dlopen(path, RTLD_NOW) != nil { return true }
        let err = dlerror().map { String(cString: $0) } ?? "?"
        dlog("dlopen \(path) falló: \(err)", sync: true)
        return false
    }

    static func methodNames(_ cls: AnyClass, filter: [String]) -> [String] {
        func list(_ c: AnyClass, prefix: String) -> [String] {
            var count: UInt32 = 0
            guard let methods = class_copyMethodList(c, &count) else { return [] }
            defer { free(methods) }
            return (0..<Int(count)).compactMap { i in
                let name = NSStringFromSelector(method_getName(methods[i]))
                let keep = filter.isEmpty || filter.contains { name.localizedCaseInsensitiveContains($0) }
                return keep ? prefix + name : nil
            }
        }
        var out = list(cls, prefix: "-")
        if let meta = object_getClass(cls) { out += list(meta, prefix: "+") }
        return out.sorted()
    }

    static func dump(_ className: String, filter: [String]) -> AnyClass? {
        guard let cls = NSClassFromString(className) else {
            dlog("[PRIVADO] clase \(className) no existe", sync: true)
            return nil
        }
        let names = methodNames(cls, filter: filter)
        dlog("[PRIVADO] \(className) métodos (\(names.count)): \(names.joined(separator: " "))", sync: true)
        return cls
    }

    private static func imp(_ target: AnyObject, _ sel: Selector) -> IMP? {
        let m: Method?
        if let cls = target as? AnyClass {
            m = class_getClassMethod(cls, sel)
        } else {
            m = class_getInstanceMethod(object_getClass(target), sel)
        }
        return m.map(method_getImplementation)
    }

    static func callObject(_ target: AnyObject, _ name: String) -> AnyObject? {
        let sel = NSSelectorFromString(name)
        guard let f = imp(target, sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        return unsafeBitCast(f, to: Fn.self)(target, sel)?.takeUnretainedValue()
    }

    static func callObject(_ target: AnyObject, _ name: String, int arg: Int) -> AnyObject? {
        let sel = NSSelectorFromString(name)
        guard let f = imp(target, sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, Int) -> Unmanaged<AnyObject>?
        return unsafeBitCast(f, to: Fn.self)(target, sel, arg)?.takeUnretainedValue()
    }

    static func callVoid(_ target: AnyObject, _ name: String, object: AnyObject, int arg: Int) -> Bool {
        let sel = NSSelectorFromString(name)
        guard let f = imp(target, sel) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, Int) -> Void
        unsafeBitCast(f, to: Fn.self)(target, sel, object, arg)
        return true
    }

    static func protect(_ label: String, _ body: () -> Void) -> String? {
        dlog("[PRIVADO] → \(label)", sync: true)
        return MCObjC.performSafely(body)
    }

    // MARK: ToneLibrary

    /// TLAlertType 1 = llamada entrante en los class-dumps conocidos (sin verificar en iOS 26).
    static let incomingCallAlertType = 1
    private static let originalToneKey = "probe.originalToneIdentifier"

    static func toneManager() -> NSObject? {
        guard load("/System/Library/PrivateFrameworks/ToneLibrary.framework/ToneLibrary"),
              let cls = dump("TLToneManager", filter: ["tone", "ringtone", "import", "current", "default", "shared"])
        else { return nil }
        for name in ["sharedToneManager", "sharedRingtoneManager"] {
            if let obj = callObject(cls as AnyObject, name) as? NSObject { return obj }
        }
        dlog("[PRIVADO] TLToneManager sin singleton conocido", sync: true)
        return nil
    }

    static func currentRingtoneIdentifier(_ mgr: NSObject) -> String? {
        callObject(mgr, "currentToneIdentifierForAlertType:", int: incomingCallAlertType) as? String
    }

    static func toneLibraryRead() -> Result {
        var detail = ""
        var outcome = Outcome.missing
        let ex = protect("TLToneManager lectura") {
            guard let mgr = toneManager() else { detail = "TLToneManager no disponible"; return }
            var parts: [String] = []
            if let id = currentRingtoneIdentifier(mgr) { parts.append("tono actual=\(id)") }
            if let def = callObject(mgr, "defaultRingtoneIdentifier") { parts.append("default=\(def)") }
            outcome = parts.isEmpty ? .missing : .readOnly
            detail = parts.isEmpty ? "ningún getter conocido respondió; revisa el volcado de métodos" : parts.joined(separator: " · ")
        }
        if let ex { return record(Result(name: "ToneLibrary lectura", outcome: .blocked, detail: "NSException \(ex)")) }
        return record(Result(name: "ToneLibrary lectura", outcome: outcome, detail: detail))
    }

    /// Experimento clave: cambiar el tono de llamada por defecto. Lee de vuelta para confirmar,
    /// porque "no crasheó" no significa "cambió" (cfprefsd puede descartar la escritura en silencio).
    static func toneLibrarySet(_ identifier: String) -> Result {
        var detail = ""
        var outcome = Outcome.missing
        let ex = protect("setCurrentToneIdentifier:\(identifier) forAlertType:\(incomingCallAlertType)") {
            guard let mgr = toneManager() else { detail = "TLToneManager no disponible"; return }
            let before = currentRingtoneIdentifier(mgr)
            if UserDefaults.standard.string(forKey: originalToneKey) == nil, let before {
                UserDefaults.standard.set(before, forKey: originalToneKey)
            }
            guard callVoid(mgr, "setCurrentToneIdentifier:forAlertType:", object: identifier as NSString, int: incomingCallAlertType) else {
                detail = "setCurrentToneIdentifier:forAlertType: no existe"
                return
            }
            let after = currentRingtoneIdentifier(mgr)
            if after == identifier && before != identifier {
                outcome = .worked
                detail = "antes=\(before ?? "nil") después=\(after ?? "nil"). CONFIRMA en Ajustes › Sonidos › Tono y con una llamada real."
            } else {
                outcome = .blocked
                detail = "invocado sin crash pero el valor no cambió (antes=\(before ?? "nil") después=\(after ?? "nil"))"
            }
        }
        if let ex { return record(Result(name: "ToneLibrary cambiar tono", outcome: .blocked, detail: "NSException \(ex)")) }
        return record(Result(name: "ToneLibrary cambiar tono", outcome: outcome, detail: detail))
    }

    static func toneLibraryRestore() -> Result {
        guard let original = UserDefaults.standard.string(forKey: originalToneKey) else {
            return record(Result(name: "ToneLibrary restaurar", outcome: .missing, detail: "no hay tono original guardado"))
        }
        let r = toneLibrarySet(original)
        if r.outcome == .worked { UserDefaults.standard.removeObject(forKey: originalToneKey) }
        return r
    }

    /// Solo comprueba si el selector de importación existe. No lo invoca: la firma del bloque
    /// de completado no está confirmada en iOS 26 y una firma errónea crashea sin excepción.
    static func toneLibraryImportAvailability() -> Result {
        var found: [String] = []
        let ex = protect("buscar selectores de importación") {
            guard let mgr = toneManager() else { return }
            found = methodNames(type(of: mgr), filter: ["import"])
        }
        if let ex { return record(Result(name: "ToneLibrary importar", outcome: .blocked, detail: "NSException \(ex)")) }
        let detail = found.isEmpty
            ? "no hay selectores de importación"
            : "existen: \(found.joined(separator: " ")) — NO invocado (firma sin confirmar). Envíame este volcado."
        return record(Result(name: "ToneLibrary importar", outcome: found.isEmpty ? .missing : .readOnly, detail: detail))
    }

    // MARK: AVSystemController (volumen por categoría)

    static func avSystemController() -> NSObject? {
        load("/System/Library/PrivateFrameworks/MediaExperience.framework/MediaExperience")
        load("/System/Library/PrivateFrameworks/Celestial.framework/Celestial")
        guard let cls = dump("AVSystemController", filter: ["olume", "ategory", "inger", "shared"]) else { return nil }
        return callObject(cls as AnyObject, "sharedAVSystemController") as? NSObject
    }

    static func ringtoneVolumeRead() -> Result {
        var detail = ""
        var outcome = Outcome.missing
        let ex = protect("AVSystemController getVolume:forCategory:") {
            guard let ctl = avSystemController() else { detail = "AVSystemController no disponible"; return }
            let sel = NSSelectorFromString("getVolume:forCategory:")
            guard let f = imp(ctl, sel) else { detail = "getVolume:forCategory: no existe"; return }
            typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Float>, AnyObject) -> Bool
            var parts: [String] = []
            for category in ["Ringtone", "Audio/Video"] {
                var v: Float = -1
                let ok = unsafeBitCast(f, to: Fn.self)(ctl, sel, &v, category as NSString)
                parts.append("\(category)=\(ok ? String(format: "%.2f", v) : "falló")")
            }
            outcome = .readOnly
            detail = parts.joined(separator: " · ")
        }
        if let ex { return record(Result(name: "Volumen de timbre (lectura)", outcome: .blocked, detail: "NSException \(ex)")) }
        return record(Result(name: "Volumen de timbre (lectura)", outcome: outcome, detail: detail))
    }

    static func ringtoneVolumeSet(_ value: Float) -> Result {
        var detail = ""
        var outcome = Outcome.missing
        let ex = protect("AVSystemController setVolumeTo:\(value) forCategory:Ringtone") {
            guard let ctl = avSystemController() else { detail = "AVSystemController no disponible"; return }
            let sel = NSSelectorFromString("setVolumeTo:forCategory:")
            guard let f = imp(ctl, sel) else { detail = "setVolumeTo:forCategory: no existe"; return }
            typealias Fn = @convention(c) (AnyObject, Selector, Float, AnyObject) -> Bool
            let ok = unsafeBitCast(f, to: Fn.self)(ctl, sel, value, "Ringtone" as NSString)
            outcome = ok ? .worked : .blocked
            detail = "devolvió \(ok). Comprueba el regulador de Ajustes › Sonidos (el valor devuelto puede mentir)."
        }
        if let ex { return record(Result(name: "Volumen de timbre (escritura)", outcome: .blocked, detail: "NSException \(ex)")) }
        return record(Result(name: "Volumen de timbre (escritura)", outcome: outcome, detail: detail))
    }

    /// Ruta 1: intenta timbre al máximo y vuelve a leer. iOS suele bloquearlo: la alternativa práctica
    /// es Ajustes › Sonidos y vibración › Tono y alertas › «Cambiar con botones» y subir con los botones físicos.
    static func ringerVolumeMaxExperiment() -> [Result] {
        let before = ringtoneVolumeRead()
        let write = ringtoneVolumeSet(1.0)
        let after = ringtoneVolumeRead()
        var note = Result(
            name: "Timbre al máximo (conclusión)",
            outcome: write.outcome == .worked ? .readOnly : .blocked,
            detail: """
            Apple separa el volumen del timbre del volumen multimedia. En builds normales (sin jailbreak) \
            AVSystemController casi nunca deja fijarlo desde una app de terceros aunque el selector exista. \
            Si no oyes diferencia: en Ajustes › Sonidos y vibración › Tono y alertas activa «Cambiar con botones» \
            y sube el volumen con los botones laterales mientras suena el tono de prueba.
            """
        )
        note = record(note)
        return [before, write, after, note]
    }

    // MARK: TelephonyUtilities / CoreTelephony

    static func tuCallCenterRead() -> Result {
        var detail = ""
        var outcome = Outcome.missing
        let ex = protect("TUCallCenter sharedInstance") {
            load("/System/Library/PrivateFrameworks/TelephonyUtilities.framework/TelephonyUtilities")
            guard let cls = dump("TUCallCenter", filter: ["call", "shared", "incoming"]),
                  let center = callObject(cls as AnyObject, "sharedInstance") else { detail = "TUCallCenter no disponible"; return }
            let calls = callObject(center, "currentCalls") as? NSArray
            outcome = .readOnly
            detail = "currentCalls=\(calls.map { "\($0.count)" } ?? "nil") (con 0 durante una llamada real ⇒ bloqueado por entitlement)"
        }
        if let ex { return record(Result(name: "TUCallCenter", outcome: .blocked, detail: "NSException \(ex)")) }
        return record(Result(name: "TUCallCenter", outcome: outcome, detail: detail))
    }

    private static var telephonyObserverInstalled = false

    /// Escucha TODAS las notificaciones de CTTelephonyCenter y las vuelca al log. Haz una
    /// llamada real después: si no aparece nada, CommCenter las bloquea sin entitlement.
    static func coreTelephonyObserve() -> Result {
        guard !telephonyObserverInstalled else {
            return record(Result(name: "CTTelephonyCenter", outcome: .readOnly, detail: "ya instalado; haz una llamada y mira el log"))
        }
        let ctPath = "/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony"
        guard load(ctPath),
              let ctHandle = dlopen(ctPath, RTLD_NOW),
              let getDefaultPtr = dlsym(ctHandle, "CTTelephonyCenterGetDefault"),
              let addObserverPtr = dlsym(ctHandle, "CTTelephonyCenterAddObserver")
        else {
            return record(Result(name: "CTTelephonyCenter", outcome: .missing, detail: "símbolos no encontrados"))
        }
        typealias GetDefault = @convention(c) () -> UnsafeRawPointer?
        typealias AddObserver = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, CFNotificationCallback, CFString?, UnsafeRawPointer?, CFNotificationSuspensionBehavior) -> Void
        let getDefault = unsafeBitCast(getDefaultPtr, to: GetDefault.self)
        let addObserver = unsafeBitCast(addObserverPtr, to: AddObserver.self)
        let ex = protect("CTTelephonyCenterAddObserver(nil name)") {
            let center = getDefault()
            let callback: CFNotificationCallback = { _, _, name, _, userInfo in
                let n = name.map { $0.rawValue as String } ?? "nil"
                let keys = userInfo.map { ($0 as NSDictionary).allKeys.map { "\($0)" }.joined(separator: ",") } ?? ""
                dlog("[CT] \(n) keys=[\(keys)]")
            }
            addObserver(center, nil, callback, nil, nil, .deliverImmediately)
            telephonyObserverInstalled = true
        }
        if let ex { return record(Result(name: "CTTelephonyCenter", outcome: .blocked, detail: "NSException \(ex)")) }
        return record(Result(name: "CTTelephonyCenter", outcome: .readOnly, detail: "observador instalado; haz una llamada real y busca líneas [CT] en el log"))
    }

    // MARK: Darwin notifications (API pública notify.h, nombres no documentados)

    private static var darwinTokens: [Int32] = []

    static func darwinSignalsStart() -> Result {
        guard darwinTokens.isEmpty else {
            return record(Result(name: "Darwin notify", outcome: .readOnly, detail: "ya activo"))
        }
        let names = ["com.apple.springboard.ringerstate", "com.apple.springboard.lockstate", "com.apple.springboard.hasBlankedScreen"]
        for name in names {
            var token: Int32 = 0
            let status = notify_register_dispatch(name, &token, DispatchQueue.main) { t in
                var state: UInt64 = 0
                notify_get_state(t, &state)
                dlog("[DARWIN] \(name) state=\(state)")
            }
            if status == 0 {
                darwinTokens.append(token)
                var state: UInt64 = 0
                notify_get_state(token, &state)
                dlog("[DARWIN] \(name) inicial state=\(state)")
            } else {
                dlog("[DARWIN] \(name) registro falló status=\(status)")
            }
        }
        return record(Result(name: "Darwin notify", outcome: darwinTokens.isEmpty ? .blocked : .readOnly,
                             detail: "\(darwinTokens.count)/\(names.count) registrados (ringerstate: el significado de 0/1 se confirma cambiando el modo silencio)"))
    }

    #endif

    // MARK: Lote

    static func runReadOnlyBatch() -> [Result] {
        #if MAGIC_PRIVATE_PROBES
        dlog("── Experimentos privados (solo lectura) ──", sync: true)
        return [toneLibraryRead(), toneLibraryImportAvailability(), ringtoneVolumeRead(),
                tuCallCenterRead(), coreTelephonyObserve(), darwinSignalsStart()]
        #else
        return [Result(name: "Experimentos privados", outcome: .notCompiled, detail: "build sin MAGIC_PRIVATE_PROBES")]
        #endif
    }
}
