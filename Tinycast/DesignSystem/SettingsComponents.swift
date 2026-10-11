import AppKit
import SwiftUI

// The few pieces more than one Settings pane or editor needs; everything else stays feature-owned.

struct SettingsTabIcon: View {
    let systemImage: String
    let tint: Color
    var size = Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let scale = size / (Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2)
        Image(systemName: SystemSymbolName.resolve(systemImage, isDark: colorScheme == .dark))
            .resizable()
            .scaledToFit()
            .frame(
                width: Theme.Size.settingsSidebarGlyph * scale,
                height: Theme.Size.settingsSidebarGlyph * scale
            )
            .foregroundStyle(tint)
            .padding(Theme.Spacing.xs * scale)
            .background(
                tint.opacity(0.1),
                in: RoundedRectangle(
                    cornerRadius: Theme.Radius.thumbnail * scale, style: .continuous))
    }
}

struct SettingsFeatureToggleLabel: View {
    let anchor: SettingsAnchor
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            SettingsTabIcon(
                systemImage: anchor.tab.systemImage, tint: .accentColor,
                size: Theme.Size.settingsRowIcon * 1.5)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                SettingsRowTitle(anchor, title)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Not `LabeledContent`: its selectable text field eats the taps a `ShortcutRecorder` needs.
struct SettingsRow<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var subtitleLineLimit = 1
    var alignment: VerticalAlignment = .center
    var labelOpacity = 1.0
    /// Set when a search result points at this row, so its title can carry the pulse.
    var anchor: SettingsAnchor?
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: alignment, spacing: Theme.Spacing.lg) {
            icon.opacity(labelOpacity)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Group {
                    if let anchor {
                        SettingsRowTitle(anchor, verbatim: title)
                    } else {
                        Text(title)
                    }
                }
                .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .truncationMode(.middle)
                        .help(subtitle)
                }
            }
            .opacity(labelOpacity)
            Spacer(minLength: Theme.Spacing.lg)
            trailing
        }
    }
}

enum SettingsListMetrics {
    static let iconSize = Theme.Size.settingsRowIcon + Theme.Spacing.xs
}

extension SettingsRow where Icon == EmptyView {
    init(
        title: String, subtitle: String? = nil, subtitleLineLimit: Int = 1,
        alignment: VerticalAlignment = .center, labelOpacity: Double = 1,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title, subtitle: subtitle, subtitleLineLimit: subtitleLineLimit,
            alignment: alignment, labelOpacity: labelOpacity, icon: { EmptyView() },
            trailing: trailing)
    }

    /// A fixed row a search result lands on, so its title is always Tinycast's own text.
    init(
        title: LocalizedStringResource, subtitle: String? = nil, subtitleLineLimit: Int = 1,
        alignment: VerticalAlignment = .center, anchor: SettingsAnchor,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: String(localized: title), subtitle: subtitle,
            subtitleLineLimit: subtitleLineLimit, alignment: alignment, anchor: anchor,
            icon: { EmptyView() }, trailing: trailing)
    }
}

struct SettingsScopeRow: View {
    let scope: String
    let path: String
    let isMissing: Bool
    let onRemove: () -> Void

    private var isFolder: Bool { (path as NSString).pathExtension != "app" }

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                if isMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("This location no longer exists.")
                }
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(scope)")
            }
        } label: {
            HStack {
                Image(nsImage: IconCache.icon(forFile: path))
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .id(IconCache.style.generation)
                    .frame(
                        width: SettingsListMetrics.iconSize
                            - (isFolder ? Theme.Spacing.xxs + 1 : 0),
                        height: SettingsListMetrics.iconSize - (isFolder ? 1 : 0)
                    )
                    .frame(
                        width: SettingsListMetrics.iconSize,
                        height: SettingsListMetrics.iconSize
                    )
                    .accessibilityHidden(true)
                Text(scope)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isMissing ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            }
        }
    }
}

extension View {
    func settingsOptionSegment(isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
        return
            self
            .frame(
                width: Theme.Size.settingsControlHeight,
                height: Theme.Size.settingsControlHeight
            )
            .contentShape(shape)
            .background {
                shape.fill(isSelected ? Theme.Colors.controlSurface : Color.clear)
            }
    }

    /// Dims as well as disables; `.disabled` alone leaves the title at full strength.
    func settingsEnabled(_ isEnabled: Bool) -> some View {
        disabled(!isEnabled).opacity(isEnabled ? 1 : 0.45)
    }

    func settingsEditorTextField() -> some View {
        modifier(SettingsEditorTextField())
    }

    func settingsEditorTextArea(height: CGFloat) -> some View {
        modifier(SettingsEditorTextArea(height: height))
    }

    /// `controlsOnGlass: false` draws the glass behind, so a control keeps its accent colour.
    func settingsEditorPanelSurface(controlsOnGlass: Bool = true) -> some View {
        modifier(SettingsEditorPanelSurface(controlsOnGlass: controlsOnGlass))
    }

    /// The one place that says hiding a row from the launcher never unbinds its shortcut.
    func launcherVisibilityHelp() -> some View {
        help("Show in launcher. Its shortcut works either way.")
    }
}

struct SettingsEditorHeader: View {
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.panelTitle)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsEditorField<Content: View>: View {
    let title: LocalizedStringResource
    var labelFont: Font?
    @ViewBuilder var content: Content

    init(
        _ title: LocalizedStringResource, labelFont: Font? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.labelFont = labelFont
        self.content = content()
    }

    var body: some View {
        LabeledContent {
            content
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } label: {
            Text(title).font(labelFont)
        }
    }
}

private struct SettingsEditorTextField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: Theme.Size.dialogButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
    }
}

private struct SettingsEditorTextArea: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .padding(Theme.Spacing.sm)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
    }
}

private struct SettingsEditorPanelSurface: ViewModifier {
    let controlsOnGlass: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        // In front of the glass: a glass fill is hit-testable and would hide a handle behind it.
        let draggable = content.background(WindowDragBackground())
        if controlsOnGlass {
            draggable
                .background(Theme.Colors.panelScrim, in: shape)
                .glassEffect(.regular, in: shape)
        } else {
            draggable.background {
                shape.fill(Theme.Colors.panelScrim).glassEffect(.regular, in: shape)
            }
        }
    }
}

struct FeatureSwitchSection: View {
    let anchor: SettingsAnchor
    let enableTitle: LocalizedStringResource
    var enableSubtitle: LocalizedStringResource?
    @Binding var isEnabled: Bool
    @Binding var showsInLauncher: Bool
    var showsIcon = false
    var showsHeader = true

    var body: some View {
        if showsHeader {
            section
        } else {
            section.settingsAnchor(anchor)
        }
    }

    private var section: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                if showsIcon, let enableSubtitle {
                    SettingsFeatureToggleLabel(
                        anchor: anchor, title: enableTitle, subtitle: enableSubtitle)
                } else {
                    SettingsRowTitle(anchor, enableTitle)
                    if let enableSubtitle { Text(enableSubtitle) }
                }
            }
            Toggle("Show in launcher", isOn: $showsInLauncher)
                // The switch above stays live so the feature can always be turned back on.
                .settingsEnabled(isEnabled)
        } header: {
            if showsHeader { SettingsSectionHeader(anchor) }
        }
    }
}

/// The filter row above a long list, shaped like a search field rather than a form text field.
struct SettingsFilterField: View {
    let prompt: LocalizedStringResource
    @Binding var query: String
    /// The plain field has no bezel: without this only the glyphs are a target.
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            // `prompt:` + `labelsHidden`, or the form makes the placeholder a left-column heading.
            TextField("", text: $query, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused($focused)
                .pointerStyle(.horizontalText)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .contentShape(.rect)
        .onTapGesture { focused = true }
    }
}
