import Foundation

public func normalizeExtensionToken(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let withoutDot = trimmed.drop { $0 == "." }
    guard !withoutDot.isEmpty else {
        return nil
    }

    let normalized = withoutDot.lowercased()
    return normalized.isEmpty ? nil : normalized
}

public func splitExtensionList(_ raw: String) -> [String] {
    var seen: Set<String> = []
    var results: [String] = []

    for part in raw.split(separator: ",", omittingEmptySubsequences: false) {
        guard let normalized = normalizeExtensionToken(String(part)) else {
            continue
        }
        if seen.insert(normalized).inserted {
            results.append(normalized)
        }
    }

    return results
}

extension URL {
    var standardizedDirectoryURL: URL {
        standardizedFileURL
    }
}
