import Foundation

/// What the App Launcher shortcut does when pressed while the palette is already open.
enum LauncherShortcutBehavior: String, CaseIterable, Identifiable, Sendable {
    case closeWindow
    case popToRootOrClose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closeWindow: return "Hide launcher"
        case .popToRootOrClose: return "Pop to root"
        }
    }
}
