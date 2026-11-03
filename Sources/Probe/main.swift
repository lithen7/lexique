import Foundation
import OpenMDict

let dir = ProcessInfo.processInfo.environment["DICT_DIR"]
    ?? NSString(string: "~/Library/Eudb_en").expandingTildeInPath
let cacheDir = URL(fileURLWithPath: NSString(string: "~/Library/Caches/Lexique/MDXIndex").expandingTildeInPath, isDirectory: true)
try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
MDictSidecarCache.cacheDirectory = cacheDir
print("索引缓存：\(cacheDir.path)\n")

let fm = FileManager.default
let files = (try? fm.contentsOfDirectory(atPath: dir))?
    .filter { $0.lowercased().hasSuffix(".mdx") }
    .sorted() ?? []

if let path = ProcessInfo.processInfo.environment["DUMP_MDX"],
   let word = ProcessInfo.processInfo.environment["DUMP_WORD"] {
    let r = try MDictReader(path: path)
    let hits = r.lookupAll(word)
    print("hits=\(hits.count)")
    print(String((hits.first?.article.html ?? "").prefix(4000)))
    exit(0)
}

if let single = ProcessInfo.processInfo.environment["SINGLE"] {
    for round in 1...2 {
        let t = Date()
        do {
            let r = try MDictReader(path: single)
            print("round \(round): \(Int(Date().timeIntervalSince(t)*1000))ms entries=\(r.entryCount) title=\(r.metadata.title ?? "-")")
        } catch { print("round \(round): \(error)") }
    }
    exit(0)
}

print("目录：\(dir)")
print("找到 \(files.count) 部 .mdx\n")

for name in files {
    let path = (dir as NSString).appendingPathComponent(name)
    let label = String(name.dropLast(4))
    let t0 = Date()
    do {
        let reader = try MDictReader(path: path)
        let meta = reader.metadata
        let openMS = Int(Date().timeIntervalSince(t0) * 1000)
        var line = "✅ \(label)\n   引擎 \(meta.engineVersion)｜加密 \(meta.isEncrypted)｜编码 \(meta.encoding)｜打开 \(openMS)ms"
        if let probe = ["history", "plant", "词"].first(where: { reader.contains($0) }) {
            let t1 = Date()
            let hits = reader.lookupAll(probe)
            let ms = Int(Date().timeIntervalSince(t1) * 1000)
            let html = hits.first?.article.html ?? ""
            line += "｜查「\(probe)」\(hits.count) 条 \(ms)ms｜正文 \(html.count) 字符"
        } else {
            line += "｜三个测试词都没命中"
        }
        print(line)
    } catch {
        print("❌ \(label)\n   \(error)")
    }
}
