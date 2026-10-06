/*
 MindtoneX Call Directory extension

 User setup (required once):
 Settings → Phone → Call Blocking & Identification → enable MindtoneX Caller Label

 While Perform is armed and a word is locked, this extension publishes the locked label
 for the caller number set in Word API settings (E.164 digits). Without it no call is labeled.

 For **any incoming number** without a known E.164, iOS 18+ Live Caller ID Lookup (PIR server)
 is required — see MagicCallLiveCallerLookup/README.md in the repo.
 */

import CallKit
import Foundation

final class CallDirectoryHandler: CXCallDirectoryProvider {
    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self
        let snapshot = CallerLabelStore.load()
        var entries = 0
        if snapshot.performArmed, snapshot.labelEnabled, !snapshot.lockedLabel.isEmpty {
            for number in snapshot.identificationPhoneNumbers {
                context.addIdentificationEntry(withNextSequentialPhoneNumber: number, label: snapshot.lockedLabel)
                entries += 1
            }
        }
        CallerLabelStore.recordLoad(snapshot, entries: entries)
        context.completeRequest()
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        extensionContext.completeRequest()
    }
}
