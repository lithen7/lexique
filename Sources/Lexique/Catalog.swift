import Foundation
import OpenMDict

struct DictRecord {
    let name: String
    let path: String
}

struct DictProfile {
    let name: String
    var dictionaries: [String]
}

final class DictionaryHandle {
    let record: DictRecord
    private(set) var reader: MDictReader?

    init(record: DictRecord) { self.record = record }

    func load() {
        do {
            let reader = try MDictReader(path: record.path)
            self.reader = reader
        } catch {
            print("failed \(record.name): \(error)")
        }
    }

    func lookup(_ word: String) -> [MDictWordEntry] {
        guard let reader else { return [] }
        return reader.lookupAll(word)
    }

    func search(_ prefix: String, limit: Int) -> [String] {
        guard let reader else { return [] }
        return reader.searchWithFallback(prefix: prefix, limit: limit, waitsForSetup: false, fallbacks: .all).keys
    }
}

final class Catalog: @unchecked Sendable {
    static let shared = Catalog()

    let directory: String
    private(set) var profiles: [DictProfile] = []
    private(set) var currentIndex = 0
    private var defaultIndex = 0
    private(set) var handles: [DictionaryHandle] = []

    private let loadQueue = DispatchQueue(label: "lexique.catalog.load", qos: .userInitiated)
    private let searchQueue = DispatchQueue(label: "lexique.search", qos: .userInitiated)
    private let lock = NSLock()

    var onChange: (() -> Void)?

    var currentProfile: DictProfile? {
        profiles.indices.contains(currentIndex) ? profiles[currentIndex] : nil
    }
    var totalCount: Int { currentProfile?.dictionaries.count ?? 0 }
    var loadedCount: Int { lock.lock(); defer { lock.unlock() }; return handles.filter { $0.reader != nil }.count }

    private init() {
        let env = ProcessInfo.processInfo.environment["LEXIQUE_DICT_DIR"]
        directory = env ?? NSString(string: "~/Library/Application Support/Lexique/Dictionaries").expandingTildeInPath

        let cache = URL(fileURLWithPath: NSString(string: "~/Library/Caches/Lexique/MDXIndex").expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        MDictSidecarCache.cacheDirectory = cache
    }

    func start() {
        profiles = discoverProfiles()
        currentIndex = defaultIndex
        loadProfile(currentIndex)
    }

    func releaseCache(profileIndex: Int) {
        guard profiles.indices.contains(profileIndex) else { return }
        if profileIndex == currentIndex {
            lock.lock()
            handles = []
            lock.unlock()
            DispatchQueue.main.async { self.onChange?() }
        }
        for name in profiles[profileIndex].dictionaries {
            let path = (directory as NSString).appendingPathComponent(name + ".mdx")
            guard let meta = MDictReader.loadMetadata(from: path), let sha = meta.headerSHA256 else { continue }
            MDictReader.removeSidecarCache(forHeaderSHA256: sha)
        }
        MDictSidecarCache.flushPendingWrites()
    }

    func switchProfile(_ index: Int) {
        guard profiles.indices.contains(index) else { return }
        let alreadyLoaded = lock.withLock { !handles.isEmpty }
        if index == currentIndex && alreadyLoaded { return }
        currentIndex = index
        loadProfile(index)
    }

    private func loadProfile(_ index: Int) {
        guard profiles.indices.contains(index) else { return }
        let names = profiles[index].dictionaries

        lock.lock()
        handles = names.map { name in
            DictionaryHandle(record: DictRecord(name: name, path: (directory as NSString).appendingPathComponent(name + ".mdx")))
        }
        let newHandles = handles
        lock.unlock()

        DispatchQueue.main.async { self.onChange?() }

        loadQueue.async {
            for handle in newHandles {
                // Stop if the user switched profiles meanwhile.
                let stillCurrent = self.lock.withLock { self.handles.contains { $0 === handle } }
                if !stillCurrent { break }
                handle.load()
                DispatchQueue.main.async { self.onChange?() }
            }
        }
    }

    private func snapshot() -> [DictionaryHandle] {
        lock.lock(); defer { lock.unlock() }
        return handles
    }

    // order.txt format:
    //   # EN-CN
    //   Oxford ...
    //   # EN-FR-CN
    //   拉鲁斯...
    private func discoverProfiles() -> [DictProfile] {
        let fm = FileManager.default
        let all = ((try? fm.contentsOfDirectory(atPath: directory)) ?? [])
            .filter { $0.lowercased().hasSuffix(".mdx") }
            .map { String($0.dropLast(4)) }
        let allSet = Set(all)

        let orderURL = URL(fileURLWithPath: directory).appendingPathComponent("order.txt")
        guard let text = try? String(contentsOf: orderURL, encoding: .utf8) else {
            return [DictProfile(name: "默认", dictionaries: all.sorted())]
        }

        var profiles: [DictProfile] = []
        var current = DictProfile(name: "默认", dictionaries: [])
        var sawSection = false
        var defaultName: String?

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.lowercased().hasPrefix("default") && line.contains("=") {
                defaultName = line.split(separator: "=", maxSplits: 1)
                    .last.map { $0.trimmingCharacters(in: .whitespaces) }
                continue
            }
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                let name = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    if sawSection || !current.dictionaries.isEmpty { profiles.append(current) }
                    current = DictProfile(name: name, dictionaries: [])
                    sawSection = true
                }
                continue
            }
            let name = line.hasSuffix(".mdx") ? String(line.dropLast(4)) : line
            if allSet.contains(name) { current.dictionaries.append(name) }
        }
        profiles.append(current)

        // Fill any dictionaries not mentioned into the first profile.
        let mentioned = Set(profiles.flatMap { $0.dictionaries })
        let leftovers = all.filter { !mentioned.contains($0) }.sorted()
        if !leftovers.isEmpty && !profiles.isEmpty {
            profiles[0].dictionaries.append(contentsOf: leftovers)
        }
        let result = profiles.filter { !$0.dictionaries.isEmpty }
        if let defaultName, let idx = result.firstIndex(where: { $0.name == defaultName }) {
            defaultIndex = idx
        }
        return result
    }

    func search(prefix: String, completion: @escaping ([(String, String)]) -> Void) {
        let current = snapshot().filter { $0.reader != nil }
        guard !prefix.isEmpty, !current.isEmpty else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        searchQueue.async {
            var best: [String: (dictIndex: Int, key: String)] = [:]
            for (index, handle) in current.enumerated() {
                for key in handle.search(prefix, limit: 20) {
                    let folding = key.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                    if let existing = best[folding] {
                        if index < existing.dictIndex { best[folding] = (index, key) }
                    } else {
                        best[folding] = (index, key)
                    }
                }
            }
            let lower = prefix.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let ranked = best.sorted { a, b in
                let aExact = a.key == lower
                let bExact = b.key == lower
                if aExact != bExact { return aExact }
                if a.value.key.count != b.value.key.count { return a.value.key.count < b.value.key.count }
                if a.value.dictIndex != b.value.dictIndex { return a.value.dictIndex < b.value.dictIndex }
                return a.value.key.localizedStandardCompare(b.value.key) == .orderedAscending
            }.map { $0.value }
            let result = ranked.prefix(9).map { ($0.key, current[$0.dictIndex].record.name) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func article(for word: String, limit: Int = 4) -> String {
        var sections: [String] = []
        for handle in snapshot() {
            if sections.count >= limit { break }
            guard let entry = handle.lookup(word).first else { continue }
            let title = handle.record.name
            sections.append("""
            <section class="lex-section">
              <div class="lex-dict">\(escape(title))</div>
              <div class="lex-body">\(entry.article.html)</div>
            </section>
            """)
        }
        if sections.isEmpty {
            return "<p style=\"opacity:.5\">No entry for “\(escape(word))” in the loaded dictionaries.</p>"
        }
        return sections.joined(separator: "\n")
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
