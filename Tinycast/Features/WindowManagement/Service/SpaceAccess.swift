import CoreGraphics
import Darwin
import Foundation

@MainActor
enum SpaceAccess {
    static func snapshot(at point: CGPoint? = nil, on displayIdentifier: String? = nil) -> SpaceNavigation? {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_NOW) else { return nil }
        defer { dlclose(handle) }
        typealias Connection = @convention(c) () -> Int32
        typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
        typealias DisplayForPoint = @convention(c) (Int32, CGPoint) -> Unmanaged<CFString>?
        guard let connectionSymbol = dlsym(handle, "SLSMainConnectionID"),
            let spacesSymbol = dlsym(handle, "SLSCopyManagedDisplaySpaces"),
            let displaySymbol = dlsym(handle, "SLSCopyBestManagedDisplayForPoint")
        else { return nil }
        let connection = unsafeBitCast(connectionSymbol, to: Connection.self)()
        let copySpaces = unsafeBitCast(spacesSymbol, to: CopySpaces.self)
        let displayForPoint = unsafeBitCast(displaySymbol, to: DisplayForPoint.self)
        let identifier: String
        if let displayIdentifier {
            identifier = displayIdentifier
        } else {
            guard let point,
                let display = displayForPoint(connection, point)?.takeRetainedValue()
            else { return nil }
            identifier = display as String
        }
        guard let displays = copySpaces(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return nil }
        return displays.lazy.compactMap(SpaceNavigation.init).first {
            $0.displayIdentifier.caseInsensitiveCompare(identifier) == .orderedSame
        }
    }
}
