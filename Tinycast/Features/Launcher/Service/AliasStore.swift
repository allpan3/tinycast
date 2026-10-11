import Foundation

/// The user's per-entry aliases, keyed like favorites and ranking by `preferenceKey`.
@MainActor
@Observable
final class AliasStore {
    private let defaults: UserDefaults
    private let defaultsKey = "launcherAliases"
    private let immediateDefaultsKey = "launcherImmediateAliases"

    private(set) var aliases: [String: String]
    private(set) var immediateAliases: Set<String>
    var hasSpaceAlias: Bool { aliases.values.contains(" ") }
    /// AppIndex includes this in its result key, invalidating a ranking when an alias changes.
    private(set) var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedAliases = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        aliases = storedAliases
        immediateAliases = Set(defaults.stringArray(forKey: immediateDefaultsKey)
            ?? storedAliases.filter { $0.value == " " }.map(\.key))
        defaults.set(immediateAliases.sorted(), forKey: immediateDefaultsKey)
    }

    func alias(for entryKey: String) -> String? { aliases[entryKey] }

    func setAlias(_ alias: String, for entryKey: String) {
        let value = Self.storedValue(alias)
        guard aliases[entryKey] != value else { return }
        aliases[entryKey] = value
        if value != " " { immediateAliases.remove(entryKey) }
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
        defaults.set(immediateAliases.sorted(), forKey: immediateDefaultsKey)
    }

    func opensImmediately(for entryKey: String) -> Bool {
        aliases[entryKey] == " " && immediateAliases.contains(entryKey)
    }

    func setOpensImmediately(_ immediate: Bool, for entryKey: String) {
        guard aliases[entryKey] == " " else { return }
        var keys = immediateAliases
        if immediate { keys.insert(entryKey) } else { keys.remove(entryKey) }
        replaceImmediateAliases(keys)
    }

    func replaceImmediateAliases(_ keys: Set<String>) {
        guard immediateAliases != keys else { return }
        immediateAliases = keys
        revision &+= 1
        defaults.set(keys.sorted(), forKey: immediateDefaultsKey)
    }

    func removeKeys(_ keys: Set<String>) {
        let remaining = aliases.filter { !keys.contains($0.key) }
        let remainingImmediate = immediateAliases.subtracting(keys)
        guard remaining.count != aliases.count || remainingImmediate != immediateAliases else { return }
        aliases = remaining
        immediateAliases = remainingImmediate
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
        defaults.set(immediateAliases.sorted(), forKey: immediateDefaultsKey)
    }

    func replace(_ new: [String: String]) {
        aliases = new.compactMapValues(Self.storedValue)
        immediateAliases = immediateAliases.filter { aliases[$0] == " " }
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
        defaults.set(immediateAliases.sorted(), forKey: immediateDefaultsKey)
    }

    private static func storedValue(_ alias: String) -> String? {
        alias == " " || !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? alias : nil
    }
}
