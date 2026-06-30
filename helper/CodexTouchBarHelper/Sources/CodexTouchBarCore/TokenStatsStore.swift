import Foundation

public final class TokenStatsStore {
    private let codexHome: URL
    private let cacheFile: URL
    private let version = 1
    private let normalDays = 2

    public init(codexHome: URL, cacheFile: URL) {
        self.codexHome = codexHome
        self.cacheFile = cacheFile
    }

    public func load(fullScan: Bool = false) -> TokenStats {
        var cache = fullScan ? emptyCache() : loadCache()
        var filesCache = cache["files"] as? JSONObject ?? [:]
        var daily = cache["daily"] as? JSONObject ?? [:]
        var total = intValue(cache["total"]) ?? 0

        for url in candidateFiles(cache: cache, fullScan: fullScan) {
            let size = fileSize(for: url)
            let key = url.path
            let entry = filesCache[key] as? JSONObject ?? [:]
            var offset = fullScan ? 0 : UInt64(intValue(entry["offset"]) ?? 0)
            if size < offset {
                offset = 0
            }
            if size == offset {
                continue
            }

            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try handle.seek(toOffset: offset)
                let tail = handle.readDataToEndOfFile()
                let modification = modificationDate(for: url)

                for part in tail.split(separator: 10, omittingEmptySubsequences: true) {
                    guard part.contains(Data(#""last_token_usage""#.utf8)) else { continue }
                    let line = String(decoding: part, as: UTF8.self)
                    guard
                        let event = parseJSONLine(line),
                        let payload = event["payload"] as? JSONObject,
                        let info = payload["info"] as? JSONObject,
                        let lastUsage = info["last_token_usage"] as? JSONObject,
                        let tokens = intValue(lastUsage["total_tokens"]),
                        tokens > 0
                    else {
                        continue
                    }

                    let key = dayKey(for: parseEventDate(event["timestamp"], fallbackModificationDate: modification))
                    daily[key] = (intValue(daily[key]) ?? 0) + tokens
                    total += tokens
                }

                filesCache[key] = [
                    "offset": Int(size),
                    "size": Int(size),
                    "mtime": modification.timeIntervalSince1970
                ]
            } catch {
                continue
            }
        }

        cache["version"] = version
        cache["files"] = filesCache
        cache["daily"] = daily
        cache["total"] = total
        try? writeJSONObject(cache, to: cacheFile)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()).map { dayKey(for: $0) } ?? ""
        return TokenStats(
            yesterdayTokens: intValue(daily[yesterday]) ?? 0,
            cumulativeTokens: total,
            yesterdayDate: yesterday
        )
    }

    private func emptyCache() -> JSONObject {
        [
            "version": version,
            "files": JSONObject(),
            "daily": JSONObject(),
            "total": 0
        ]
    }

    private func loadCache() -> JSONObject {
        guard
            let cache = try? readJSONObject(from: cacheFile),
            intValue(cache["version"]) == version
        else {
            return emptyCache()
        }
        var normalized = cache
        if normalized["files"] as? JSONObject == nil {
            normalized["files"] = JSONObject()
        }
        if normalized["daily"] as? JSONObject == nil {
            normalized["daily"] = JSONObject()
        }
        normalized["total"] = intValue(normalized["total"]) ?? 0
        return normalized
    }

    private func candidateFiles(cache: JSONObject, fullScan: Bool) -> [URL] {
        let sessionRoot = codexHome.appendingPathComponent("sessions")
        if fullScan {
            return jsonlFiles(under: sessionRoot).sorted { modificationDate(for: $0) < modificationDate(for: $1) }
        }

        var candidates: [String: URL] = [:]
        for offset in 0..<normalDays {
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            let dayDirectory = sessionRoot
                .appendingPathComponent(String(format: "%04d", components.year ?? 1970))
                .appendingPathComponent(String(format: "%02d", components.month ?? 1))
                .appendingPathComponent(String(format: "%02d", components.day ?? 1))
            guard let items = try? FileManager.default.contentsOfDirectory(at: dayDirectory, includingPropertiesForKeys: [.isRegularFileKey]) else {
                continue
            }
            for url in items where url.pathExtension == "jsonl" {
                candidates[url.path] = url
            }
        }

        let filesCache = cache["files"] as? JSONObject ?? [:]
        for (path, value) in filesCache {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let entry = value as? JSONObject ?? [:]
            let offset = UInt64(intValue(entry["offset"]) ?? 0)
            if fileSize(for: url) > offset {
                candidates[url.path] = url
            }
        }

        return Array(candidates.values).sorted { modificationDate(for: $0) < modificationDate(for: $1) }
    }
}
