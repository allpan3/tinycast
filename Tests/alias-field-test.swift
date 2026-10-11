import AppKit
import SwiftUI

struct AppEntry {
    let preferenceKey: String
    let name: String
}

@main
@MainActor
struct AliasFieldTests {
    private static var failures = 0

    static func main() {
        _ = NSApplication.shared
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            testField(appearance: appearance)
        }
        print("Alias field tests: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testField(appearance: NSAppearance.Name) {
        let suite = "alias-field-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let aliases = AliasStore(defaults: defaults)
        let key = "command:search-files"
        aliases.setAlias(" ", for: key)
        let hosting = NSHostingView(
            rootView: AliasField(key: key, name: "Search Files")
                .environment(aliases)
                .frame(width: 140, height: 32))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 140, height: 32),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        defer { window.close() }
        window.orderFront(nil)
        settle(hosting)
        guard let editor = findEditor(in: hosting) else {
            check(false, "the actual alias field mounts its native editor")
            return
        }
        check(editor.string == " ", "Space's native text stays blank in \(appearance.rawValue)")
        check(editor.accessibilityValue() == "Space", "accessibility reads Space without inserting it")
        check(editor.string == " ", "reading accessibility cannot change the alias")
        check(!aliases.opensImmediately(for: key), "a new Space alias requires Enter")
        aliases.setOpensImmediately(true, for: key)
        settle(hosting)
        check(editor.string == " ", "changing activation cannot insert a second Space label")
        window.makeFirstResponder(editor)
        settle(hosting)
        check(editor.string == " ", "focusing Space cannot turn it into the word Space")
        window.makeFirstResponder(nil)
        settle(hosting)
        check(aliases.alias(for: key) == " ", "focus loss preserves the saved Space alias")
        aliases.setAlias("files", for: key)
        settle(hosting)
        check(editor.string == "files", "a normal alias still displays its actual text")
        check(editor.accessibilityValue() == "files", "normal alias accessibility stays native")
        aliases.setAlias(" ", for: key)
        settle(hosting)
        window.makeFirstResponder(editor)
        editor.selectAll(nil)
        editor.insertText("f", replacementRange: editor.selectedRange())
        settle(hosting)
        window.makeFirstResponder(nil)
        settle(hosting)
        check(aliases.alias(for: key) == "f", "editing Space commits the user's replacement")
        check(!aliases.opensImmediately(for: key), "letter replacements cannot inherit auto-activation")
        aliases.setAlias("", for: key)
        settle(hosting)
        check(editor.string.isEmpty, "clearing an alias empties the native editor")
    }

    private static func settle(_ hosting: NSView) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        hosting.layoutSubtreeIfNeeded()
    }

    private static func findEditor(in view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView { return editor }
        return view.subviews.lazy.compactMap { findEditor(in: $0) }.first
    }

    private static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}
