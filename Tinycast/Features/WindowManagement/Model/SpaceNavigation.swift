import Foundation

struct SpaceNavigation: Sendable {
    let displayIdentifier: String
    let currentSpace: UInt64
    let spaces: [UInt64]

    init?(_ display: [String: Any]) {
        guard let identifier = display["Display Identifier"] as? String,
            let current = display["Current Space"] as? [String: Any],
            let currentSpace = current["id64"] as? UInt64,
            let entries = display["Spaces"] as? [[String: Any]]
        else { return nil }
        let spaces = entries.compactMap { $0["id64"] as? UInt64 }
        guard !identifier.isEmpty, spaces.count == entries.count,
            Set(spaces).count == spaces.count, spaces.contains(currentSpace)
        else { return nil }
        displayIdentifier = identifier
        self.currentSpace = currentSpace
        self.spaces = spaces
    }

    func destination(_ direction: SpaceDirection) -> UInt64? {
        guard let index = spaces.firstIndex(of: currentSpace) else { return nil }
        let destination = direction == .next ? index + 1 : index - 1
        return spaces.indices.contains(destination) ? spaces[destination] : nil
    }
}
