/*
 Live Caller ID Lookup (iOS 18+) — placeholder extension target.

 Apple requires a PIR-backed serviceURL + tokenIssuerURL; the on-device extension does not
 read App Group state directly. Deploy Apple's PIR sample server with a database keyed by
 perform armed + locked label to return labels for arbitrary incoming numbers.

 Enable in Settings → Phone → Call Blocking & Identification alongside Call Directory.

 Until the PIR backend is deployed, use Call Directory + optional fallback E.164 in Word API.
 */

import Foundation
import IdentityLookup

@available(iOS 18.0, *)
@main
struct LiveCallerLookupExtension: LiveCallerIDLookupProtocol {
    var context: LiveCallerIDLookupExtensionContext {
        LiveCallerIDLookupExtensionContext(
            serviceURL: URL(string: "https://mindtonex-placeholder.invalid/pir/service")!,
            tokenIssuerURL: URL(string: "https://mindtonex-placeholder.invalid/pir/issuer")!,
            userTierToken: Data(base64Encoded: "BBBB") ?? Data()
        )
    }
}
