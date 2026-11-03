import AppKit
import Foundation

final class HistoryStore {
    static let shared = HistoryStore()

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var directory: URL {
        URL(fileURLWithPath: Catalog.shared.directory).appendingPathComponent("history", isDirectory: true)
    }

    private func fileURL(for profile: String) -> URL {
        directory.appendingPathComponent(profile + ".txt")
    }

    func record(_ word: String, profile: String) {
        guard !word.isEmpty else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = fileURL(for: profile)
        let today = formatter.string(from: Date())
        var lines: [String] = []
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
        if lines.last == "" { lines.removeLast() }
        if !lines.contains("## " + today) {
            if !lines.isEmpty { lines.append("") }
            lines.append("## " + today)
        }
        if lines.last != word { lines.append(word) }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func revealInFinder() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}
