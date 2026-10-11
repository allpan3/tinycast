import Foundation

/// Upstream semver, with an optional fourth field for a local release above its stable base.
struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    /// Nil on a stable release, which outranks every prerelease of the same triple.
    let beta: Int?
    let localRevision: Int?

    init?(_ text: String) {
        var body = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        // Release tags carry a leading `v`; `CFBundleShortVersionString` never does.
        if body.first == "v" { body = body.dropFirst() }

        let halves = body.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = halves[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3 || numbers.count == 4,
            let major = Self.number(numbers[0]),
            let minor = Self.number(numbers[1]),
            let patch = Self.number(numbers[2])
        else { return nil }

        if numbers.count == 4 {
            guard halves.count == 1, let revision = Self.number(numbers[3]), revision > 0
            else { return nil }
            localRevision = revision
        } else {
            localRevision = nil
        }

        if halves.count == 2 {
            // `beta` is the only prerelease channel that ships, so anything else is unreadable.
            let suffix = halves[1].split(separator: ".", omittingEmptySubsequences: false)
            guard suffix.count == 2, suffix[0] == "beta", let count = Self.number(suffix[1])
            else { return nil }
            beta = count
        } else {
            beta = nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var isPrerelease: Bool { beta != nil }

    var description: String {
        let triple = "\(major).\(minor).\(patch)"
        if let localRevision { return "\(triple).\(localRevision)" }
        return beta.map { "\(triple)-beta.\($0)" } ?? triple
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.beta, rhs.beta) {
        case (nil, nil): return (lhs.localRevision ?? 0) < (rhs.localRevision ?? 0)
        // A prerelease leads to its release, so it sorts below one and never above it.
        case (.some, nil): return true
        case (nil, .some): return false
        case (.some(let left), .some(let right)): return left < right
        }
    }

    /// Rejects a signed or padded field, which `Int` would silently reinterpret.
    private static func number(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}

extension AppVersion: Codable {
    init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = AppVersion(text) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(), debugDescription: "Not a version: \(text)")
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
