import Foundation
import Darwin

typealias JSONObject = [String: Any]

enum UsageError: LocalizedError {
    case missingAccessToken(URL)
    case invalidJSON(URL)
    case noLocalRateLimits
    case noLocalTokenUsage
    case noUsableUsage(String)

    var errorDescription: String? {
        switch self {
        case .missingAccessToken(let url):
            return "no access_token in \(url.path)"
        case .invalidJSON(let url):
            return "invalid JSON: \(url.path)"
        case .noLocalRateLimits:
            return "no local session rate_limits found"
        case .noLocalTokenUsage:
            return "no local session token usage found"
        case .noUsableUsage(let message):
            return message
        }
    }
}

func readJSONObject(from url: URL) throws -> JSONObject {
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? JSONObject else {
        throw UsageError.invalidJSON(url)
    }
    return object
}

func writeJSONObject(_ object: JSONObject, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
    try data.write(to: temporaryURL, options: .atomic)
    _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
}

func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    return nil
}

func doubleValue(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? NSNumber { return value.doubleValue }
    if let value = value as? String { return Double(value) }
    return nil
}

func stringValue(_ value: Any?) -> String? {
    if let value = value as? String, !value.isEmpty { return value }
    return nil
}

func timestampValue(_ value: Any?) -> Int? {
    if let timestamp = intValue(value) { return timestamp }
    guard let text = stringValue(value) else { return nil }

    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: text) {
        return Int(date.timeIntervalSince1970)
    }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: text).map { Int($0.timeIntervalSince1970) }
}

func intAtPath(_ object: JSONObject, _ path: String...) -> Int? {
    var current: Any? = object
    for key in path {
        guard let dictionary = current as? JSONObject else { return nil }
        current = dictionary[key]
    }
    return intValue(current)
}

func parseJSONLine(_ line: String) -> JSONObject? {
    guard let data = line.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? JSONObject
}

func dayKey(for date: Date, calendar: Calendar = .current) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
}

func parseEventDate(_ timestamp: Any?, fallbackModificationDate: Date) -> Date {
    guard let timestamp = timestamp as? String, !timestamp.isEmpty else {
        return fallbackModificationDate
    }

    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: timestamp) {
        return date
    }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: timestamp) ?? fallbackModificationDate
}

func modificationDate(for url: URL) -> Date {
    guard let metadata = fileMetadata(for: url) else { return .distantPast }
    let seconds = TimeInterval(metadata.st_mtimespec.tv_sec)
    let nanoseconds = TimeInterval(metadata.st_mtimespec.tv_nsec) / 1_000_000_000
    return Date(timeIntervalSince1970: seconds + nanoseconds)
}

func fileSize(for url: URL) -> UInt64 {
    guard let metadata = fileMetadata(for: url), metadata.st_size >= 0 else { return 0 }
    return UInt64(metadata.st_size)
}

private func fileMetadata(for url: URL) -> stat? {
    var metadata = stat()
    let result: Int32 = url.withUnsafeFileSystemRepresentation { path in
        guard let path else { return Int32(-1) }
        return Darwin.lstat(path, &metadata)
    }
    return result == 0 ? metadata : nil
}

func jsonlFiles(under root: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    return enumerator.compactMap { item in
        guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true ? url : nil
    }
}

func reverseLines(at url: URL, chunkSize: Int = 16_384, stopWhen handler: (String) -> Bool) throws {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var position = try handle.seekToEnd()
    var pending = Data()

    while position > 0 {
        let readSize = Int(min(UInt64(chunkSize), position))
        position -= UInt64(readSize)
        try handle.seek(toOffset: position)

        var combined = handle.readData(ofLength: readSize)
        combined.append(pending)

        let parts = combined.split(separator: 10, omittingEmptySubsequences: false)
        pending = Data(parts.first ?? Data.SubSequence())

        guard parts.count > 1 else { continue }
        for part in parts.dropFirst().reversed() where !part.isEmpty {
            if handler(String(decoding: part, as: UTF8.self)) {
                return
            }
        }
    }

    if !pending.isEmpty {
        _ = handler(String(decoding: pending, as: UTF8.self))
    }
}
