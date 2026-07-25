import Foundation
import AppKit

struct RecordingItem: Identifiable, Equatable {
    let id: URL
    let url: URL
    let date: Date
    let sizeMB: Double

    var displayName: String { url.lastPathComponent }
}

/// Lists saved recordings from ~/Movies/Teleprompter.
@MainActor
final class RecordingsStore: ObservableObject {
    @Published var items: [RecordingItem] = []
    @Published var lastRecordingURL: URL?

    init() {
        refresh()
    }

    func refresh() {
        let dir = CaptureManager.recordingsDirectory
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        items = urls
            .filter { $0.pathExtension.lowercased() == "mov" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                return RecordingItem(
                    id: url,
                    url: url,
                    date: values?.creationDate ?? .distantPast,
                    sizeMB: Double(values?.fileSize ?? 0) / 1_048_576.0
                )
            }
            .sorted { $0.date > $1.date }
    }

    func revealInFinder(_ item: RecordingItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: RecordingItem) {
        NSWorkspace.shared.open(item.url)
    }

    func openFolder() {
        NSWorkspace.shared.open(CaptureManager.recordingsDirectory)
    }
}
