import Foundation

final class IPAStore {
    static let shared = IPAStore()

    private var uk: [String: String] = [:]
    private var us: [String: String] = [:]
    private var loaded = false

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        uk = Self.parse("en_UK")
        us = Self.parse("en_US")
    }

    private static func parse(_ name: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var map: [String: String] = [:]
        map.reserveCapacity(140_000)
        for line in text.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let word = String(line[line.startIndex..<tab]).lowercased()
            var ipa = String(line[line.index(after: tab)...])
            if let comma = ipa.firstIndex(of: ",") { ipa = String(ipa[ipa.startIndex..<comma]) }
            map[word] = ipa.trimmingCharacters(in: .whitespaces)
        }
        return map
    }

    func british(_ word: String) -> String? { uk[word.lowercased()] }
    func american(_ word: String) -> String? { us[word.lowercased()] }
}
