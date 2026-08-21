import Foundation
import AppKit

final class NotificationToken: NSObject, @unchecked Sendable {}

struct AppEntry: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let nameLower: String
    let fileName: String
    let fileNameLower: String
    let path: String
    let bundleIdentifier: String?
    let url: URL
    let isSystem: Bool

    init(
        name: String,
        path: String,
        bundleIdentifier: String?,
        url: URL,
        fileName: String? = nil,
        isSystem: Bool = false
    ) {
        self.id = path
        self.name = name
        self.nameLower = name.lowercased()
        self.fileName = fileName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        self.fileNameLower = self.fileName.lowercased()
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.url = url
        self.isSystem = isSystem
    }

    func icon(size: CGFloat = 32) -> NSImage {
        AppIconCache.image(for: path, size: size)
    }
}

enum AppIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for path: String, size: CGFloat) -> NSImage {
        let key = "\(path)#\(Int(size))" as NSString
        if let hit = cache.object(forKey: key) {
            return hit
        }
        let source = NSWorkspace.shared.icon(forFile: path)
        let image = (source.copy() as? NSImage) ?? NSImage(size: NSSize(width: size, height: size))
        image.size = NSSize(width: size, height: size)
        cache.setObject(image, forKey: key)
        return image
    }

    static func removeAll() {
        cache.removeAllObjects()
    }
}

enum SearchResultKind: Sendable {
    case app
    case calculation
    case currency
}

struct SearchResult: Identifiable, Sendable {
    let id: String
    let kind: SearchResultKind
    let title: String
    let subtitle: String
    let score: Int
    let app: AppEntry?
    let copyValue: String?
    let action: @Sendable () -> Void

    init(
        id: String,
        kind: SearchResultKind,
        title: String,
        subtitle: String,
        score: Int,
        app: AppEntry? = nil,
        copyValue: String? = nil,
        action: @escaping @Sendable () -> Void
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.score = score
        self.app = app
        self.copyValue = copyValue
        self.action = action
    }
}
