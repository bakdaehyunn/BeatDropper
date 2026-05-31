import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    func loadDroppedFileURLs(from providers: [NSItemProvider]) -> Bool {
        let fileURLProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileURLProviders.isEmpty else {
            return false
        }

        let group = DispatchGroup()
        let accumulator = DroppedFileURLAccumulator()

        for provider in fileURLProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = Self.droppedFileURL(from: item) {
                    accumulator.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let urls = accumulator.snapshot()
            if urls.isEmpty {
                model.notice = "No supported audio files"
            } else {
                model.openDroppedItemsAsSet(urls)
            }
        }

        return true
    }

    nonisolated static func droppedFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url.isFileURL ? url : nil
        }

        if let data = item as? Data,
           let text = String(data: data, encoding: .utf8),
           let url = URL(string: text) {
            return url.isFileURL ? url : nil
        }

        if let string = item as? String,
           let url = URL(string: string) {
            return url.isFileURL ? url : nil
        }

        if let string = item as? NSString,
           let url = URL(string: string as String) {
            return url.isFileURL ? url : nil
        }

        return nil
    }
}
