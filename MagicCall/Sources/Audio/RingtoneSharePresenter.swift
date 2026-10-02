import LinkPresentation
import QuickLook
import UIKit

/// Presenta el audio con el tipo correcto y oculta destinos que no sirven.
/// Apple **no** permite mostrar solo «Usar como tono»: es una extensión del sistema.
enum RingtoneSharePresenter {
    private static let excluded: [UIActivity.ActivityType] = [
        .postToFacebook, .postToTwitter, .postToWeibo, .postToTencentWeibo,
        .message, .mail, .print, .copyToPasteboard, .assignToContact,
        .saveToCameraRoll, .addToReadingList, .postToFlickr, .postToVimeo,
        .airDrop, .openInIBooks, .markupAsPDF,
    ]

    /// One-shot callback for the next Share sheet: (activity type, completed).
    @MainActor static var onNextCompletion: ((String?, Bool) -> Void)?

    @MainActor
    static func present(url: URL, title: String, from presenter: UIViewController? = nil) {
        let top = presenter ?? topViewController()
        guard let top else {
            dlog("✗ No hay ventana para Compartir")
            return
        }
        let item = RingtoneActivityItem(url: url, title: title)
        let sheet = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        sheet.excludedActivityTypes = excluded
        sheet.completionWithItemsHandler = { activity, completed, _, error in
            let id = activity?.rawValue ?? "ninguna"
            dlog("Compartir: actividad=\(id) completado=\(completed)\(error.map { " error=\($0.localizedDescription)" } ?? "")")
            MainActor.assumeIsolated {
                let callback = onNextCompletion
                onNextCompletion = nil
                callback?(activity?.rawValue, completed)
            }
        }
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        }
        top.present(sheet, animated: true)
        dlog("Hoja Compartir (audio optimizado)")
    }

    @MainActor
    static func presentQuickLook(url: URL, title: String) {
        guard let top = topViewController() else { return }
        let ql = RingtoneQuickLookController(items: [RingtonePreviewItem(url: url, title: title)])
        top.present(ql, animated: true)
        dlog("Vista previa → Compartir arriba → «Usar como tono»")
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        guard var top = UIApplication.mcKeyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

private final class RingtoneActivityItem: NSObject, UIActivityItemSource {
    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { url }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { url }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        "public.mpeg-4-audio"
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let meta = LPLinkMetadata()
        meta.title = title
        meta.originalURL = url
        meta.url = url
        return meta
    }
}

private final class RingtonePreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?
    init(url: URL, title: String) {
        previewItemURL = url
        previewItemTitle = title
    }
}

private final class RingtoneQuickLookController: QLPreviewController, QLPreviewControllerDataSource {
    private let items: [QLPreviewItem]

    init(items: [QLPreviewItem]) {
        self.items = items
        super.init(nibName: nil, bundle: nil)
        dataSource = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { items.count }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        items[index]
    }
}
