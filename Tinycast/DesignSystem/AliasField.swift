import AppKit
import SwiftUI

private final class AliasTextView: NSTextView {
    override func accessibilityValue() -> String? {
        string == " " ? "Space" : super.accessibilityValue()
    }

    func alignSpaceCaret() {
        var inset: CGFloat = 0
        if string == " ", let font {
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            inset = ("Space" as NSString).size(withAttributes: attributes).width
            if selectedRange().location == 1 {
                inset -= (" " as NSString).size(withAttributes: attributes).width
            }
        }
        if textContainerInset.width != inset { textContainerInset.width = inset }
    }
}

private struct AliasTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let onCancel: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> AliasTextView {
        let editor = AliasTextView()
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.backgroundColor = .clear
        editor.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        editor.textContainerInset = NSSize(width: 0, height: 5.5)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.maximumNumberOfLines = 1
        editor.textContainer?.lineBreakMode = .byTruncatingTail
        editor.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        editor.setAccessibilityRole(.textField)
        return editor
    }

    func updateNSView(_ editor: AliasTextView, context: Context) {
        context.coordinator.field = self
        if editor.string != text { editor.string = text }
        editor.isEditable = isEnabled
        editor.isSelectable = isEnabled
        editor.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        editor.alignSpaceCaret()
        if !focused, editor.window?.firstResponder === editor {
            editor.window?.makeFirstResponder(nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var field: AliasTextField

        init(_ field: AliasTextField) {
            self.field = field
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? AliasTextView else { return }
            editor.alignSpaceCaret()
            field.text = editor.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? AliasTextView)?.alignSpaceCaret()
        }

        func textView(
            _ textView: NSTextView, shouldChangeTextIn range: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacementString, replacementString.contains(where: \.isNewline) else {
                return true
            }
            textView.insertText(
                String(replacementString.map { $0.isNewline ? " " : $0 }),
                replacementRange: range)
            return false
        }

        func textDidBeginEditing(_ notification: Notification) {
            field.focused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            field.focused = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                textView.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.insertTab(_:)):
                textView.window?.recalculateKeyViewLoop()
                textView.window?.selectNextKeyView(textView)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.recalculateKeyViewLoop()
                textView.window?.selectPreviousKeyView(textView)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                field.onCancel()
                textView.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }
    }
}

/// Dressed like `ShortcutRecorder`; the persistent AppKit field preserves focus across updates.
struct AliasField: View {
    /// The owner's `preferenceKey`, taken raw so a row without an `AppEntry` can carry one too.
    let key: String
    let name: String
    @Environment(AliasStore.self) private var aliases
    @State private var draft = ""
    @State private var focused = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        HStack(spacing: Theme.Spacing.xs) {
            ZStack(alignment: .leading) {
                if draft.isEmpty || draft == " " {
                    Text(draft.isEmpty ? "Add Alias" : "Space")
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(draft.isEmpty ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                AliasTextField(text: $draft, focused: $focused, onCancel: revert)
                    .focusEffectDisabled()
                    // The pane's `releasesFocusOnOutsideClick` resigns; this catches it landing.
                    .onChange(of: focused) { _, now in
                        if !now { commit() }
                    }
            }
            if draft == " " {
                Menu {
                    Picker("Activation", selection: immediateActivation) {
                        Text("Press Enter").tag(false)
                        Text("Open Immediately").tag(true)
                    }
                } label: {
                    Image(systemName: aliases.opensImmediately(for: key) ? "bolt.fill" : "return")
                        .font(Theme.Typography.keyCap)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Space alias activation for \(name): "
                    + (aliases.opensImmediately(for: key) ? "Open Immediately" : "Press Enter"))
                .help(aliases.opensImmediately(for: key)
                    ? "Press Space to open immediately." : "Press Space, then Enter to open.")
            }
            if !draft.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear alias for \(name)")
            }
        }
        .onAppear { draft = aliases.alias(for: key) ?? "" }
        // A backup import replaces the table out from under an unfocused row.
        .onChange(of: aliases.revision) { _, _ in
            if !focused { draft = aliases.alias(for: key) ?? "" }
        }
        // A reused table row hands the field another entry; unsaved text belongs to the old one.
        .onChange(of: key) { old, new in
            if focused {
                aliases.setAlias(draft, for: old)
                focused = false
            }
            draft = aliases.alias(for: new) ?? ""
        }
        .padding(.horizontal, Theme.Spacing.sm + 1)
        .frame(width: Theme.Size.shortcutRecorder, height: 24)
        .background(shape.fill(Theme.Colors.cardFill))
        .overlay(shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
        .clipShape(shape)
        .accessibilityLabel("Alias for \(name)")
    }

    private func commit() {
        aliases.setAlias(draft, for: key)
        draft = aliases.alias(for: key) ?? ""
    }

    private var immediateActivation: Binding<Bool> {
        Binding(
            get: { aliases.opensImmediately(for: key) },
            set: {
                commit()
                aliases.setOpensImmediately($0, for: key)
            })
    }

    private func revert() {
        draft = aliases.alias(for: key) ?? ""
        focused = false
    }

    private func clear() {
        draft = ""
        commit()
    }
}

extension AliasField {
    init(entry: AppEntry) {
        self.init(key: entry.preferenceKey, name: entry.name)
    }
}
