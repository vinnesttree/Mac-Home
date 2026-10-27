import AppKit
import SwiftUI

/// How a tile opens.
enum EntryKind: String, Codable {
    /// A web app shown full screen inside MacHome.
    case web
    /// A web address opened in a separate browser app.
    case browser
    /// A Mac app.
    case app
    /// Hides MacHome and shows the normal desktop.
    case desktop
}

/// What the gamepad does while a tile's app is in front.
enum InputProfile: String, Codable {
    /// D-pad and left stick send arrow keys, A sends Return.
    case keys
    /// Left stick moves the mouse pointer, A clicks.
    case pointer
    /// The app reads the controller itself; MacHome only listens for Home.
    case native
}

/// One tile as written in apps.json.
struct EntryConfig: Codable {
    var title: String
    var subtitle: String?
    var kind: EntryKind
    var url: String?
    var app: String?
    var browser: String?
    var arguments: [String]?
    var userAgent: String?
    var blockCodecs: [String]?
    var input: InputProfile?
    var colors: [String]?
    var symbol: String?
    var image: String?
}

struct AppsFile: Codable {
    var apps: [EntryConfig]
}

/// A tile ready to show: apps.json values plus everything looked up on this Mac.
struct LauncherEntry: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let kind: EntryKind
    let input: InputProfile
    let url: URL?
    let appURL: URL?
    let userAgent: String?
    let blockCodecs: [String]
    let arguments: [String]
    let colors: [Color]
    let symbol: String?
    let icon: NSImage?
    let artwork: NSImage?
    /// Why the tile can't open, if it can't.
    let problem: String?

    init(config: EntryConfig, baseDirectory: URL) {
        title = config.title
        subtitle = config.subtitle
        kind = config.kind
        input = config.input ?? (config.kind == .web ? .keys : .pointer)
        userAgent = config.userAgent
        blockCodecs = config.blockCodecs ?? []
        arguments = config.arguments ?? []
        symbol = config.symbol
        colors = LauncherEntry.gradient(config.colors, kind: config.kind)
        artwork = config.image.flatMap { LauncherEntry.loadImage($0, relativeTo: baseDirectory) }

        var url: URL?
        var appURL: URL?
        var problem: String?
        switch config.kind {
        case .web, .browser:
            url = LauncherEntry.webURL(config.url)
            if url == nil {
                problem = "Add a web address (http:// or https://) as \"url\" in apps.json. Press ⌘, to edit it."
            }
            if config.kind == .browser, let target = url {
                if let browser = config.browser {
                    appURL = LauncherEntry.findApp(browser)
                    if appURL == nil { problem = "\(browser) isn't installed." }
                } else {
                    appURL = NSWorkspace.shared.urlForApplication(toOpen: target)
                }
            }
        case .app:
            if let reference = config.app {
                appURL = LauncherEntry.findApp(reference)
                if appURL == nil { problem = "\(reference) isn't installed." }
            } else {
                problem = "Add the app's bundle ID or path as \"app\" in apps.json."
            }
        case .desktop:
            break
        }
        self.url = url
        self.appURL = appURL
        self.problem = problem

        if config.kind == .app, config.symbol == nil, let appURL = appURL {
            icon = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            icon = nil
        }
    }

    private static func webURL(_ string: String?) -> URL? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// Accepts a bundle ID ("com.apple.Safari"), a path, or an app name ("Kodi.app").
    private static func findApp(_ reference: String) -> URL? {
        guard reference.contains("/") || reference.hasSuffix(".app") else {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: reference)
        }
        var candidates = [(reference as NSString).expandingTildeInPath]
        if !reference.contains("/") {
            let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", NSHomeDirectory() + "/Applications"]
            candidates = folders.map { $0 + "/" + reference }
        }
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    private static func loadImage(_ path: String, relativeTo base: URL) -> NSImage? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : base.appendingPathComponent(expanded)
        return NSImage(contentsOf: url)
    }

    private static func gradient(_ hexes: [String]?, kind: EntryKind) -> [Color] {
        let parsed = (hexes ?? []).compactMap(color(hex:))
        if parsed.count >= 2 { return parsed }
        if let only = parsed.first { return [only, only] }
        if kind == .app { return [Color(white: 0.24), Color(white: 0.1)] }
        return [Color(red: 0.37, green: 0.36, blue: 0.9), Color(red: 0.12, green: 0.11, blue: 0.3)]
    }

    private static func color(hex: String) -> Color? {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}

/// Reads ~/Library/Application Support/MacHome/apps.json, creating it with the default tiles on first run.
final class ConfigStore {
    let directory: URL
    let fileURL: URL
    private var loadedDate: Date?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        directory = support.appendingPathComponent("MacHome", isDirectory: true)
        fileURL = directory.appendingPathComponent("apps.json")
    }

    var hasChanges: Bool {
        modificationDate() != loadedDate
    }

    func ensureFile() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(ConfigStore.defaultJSON.utf8).write(to: fileURL, options: .atomic)
    }

    func load() throws -> [EntryConfig] {
        try ensureFile()
        // Remember the date even if parsing fails, so a broken file is reported once rather than on every return home.
        loadedDate = modificationDate()
        var text = try String(contentsOf: fileURL, encoding: .utf8)
        // TextEdit turns typed quotes into curly ones unless Smart Quotes is off, which breaks JSON.
        text = text.replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
        return try JSONDecoder().decode(AppsFile.self, from: Data(text.utf8)).apps
    }

    static var defaultEntries: [EntryConfig] {
        (try? JSONDecoder().decode(AppsFile.self, from: Data(defaultJSON.utf8)).apps) ?? []
    }

    static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        switch decodingError {
        case .dataCorrupted(let context):
            let underlying = context.underlyingError as NSError?
            return underlying?.userInfo[NSDebugDescriptionErrorKey] as? String ?? context.debugDescription
        case .keyNotFound(let key, let context):
            return "missing \"\(key.stringValue)\" in \(path(context.codingPath))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(context.debugDescription) (\(path(context.codingPath)))"
        @unknown default:
            return decodingError.localizedDescription
        }
    }

    private static func path(_ codingPath: [CodingKey]) -> String {
        codingPath.map { $0.intValue.map { "#\($0 + 1)" } ?? $0.stringValue }.joined(separator: " › ")
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    // The YouTube user agent is the PS4 "Leanback Shell" one used by github.com/marcosrg9/YouTubeTV;
    // YouTube only serves its TV interface to TV and console user agents.
    static let defaultJSON = """
    {
      "apps": [
        {
          "title": "YouTube",
          "subtitle": "YouTube's TV interface. Videos are kept to H.264, which this Mac decodes in hardware.",
          "kind": "web",
          "url": "https://www.youtube.com/tv",
          "userAgent": "Mozilla/5.0 (PS4; Leanback Shell) Gecko/20100101 Firefox/65.0 LeanbackShell/01.00.01.75 Sony PS4/ (PS4, , no, CH)",
          "blockCodecs": ["vp9", "vp09", "av01"],
          "input": "keys",
          "symbol": "play.rectangle.fill",
          "colors": ["#FF3B30", "#8E0E0E"]
        },
        {
          "title": "Netflix",
          "subtitle": "Opens in Safari. Left stick moves the pointer, A clicks, Y toggles full screen.",
          "kind": "browser",
          "url": "https://www.netflix.com",
          "browser": "com.apple.Safari",
          "input": "pointer",
          "symbol": "film.fill",
          "colors": ["#E50914", "#2B0000"]
        },
        {
          "title": "Jellyfin",
          "subtitle": "Your media server. Choose Display mode › TV in Jellyfin's display settings.",
          "kind": "web",
          "url": "",
          "blockCodecs": ["hvc1", "hev1", "vp09", "vp9", "av01"],
          "input": "keys",
          "symbol": "tv.fill",
          "colors": ["#AA5CC3", "#00A4DC"]
        },
        {
          "title": "Safari",
          "subtitle": "Browse the web. Left stick moves the pointer, A clicks, right stick scrolls.",
          "kind": "app",
          "app": "com.apple.Safari",
          "input": "pointer"
        },
        {
          "title": "Desktop",
          "subtitle": "Use the Mac desktop. Press Home, or View and Menu together, to come back.",
          "kind": "desktop",
          "symbol": "desktopcomputer",
          "colors": ["#5E5CE6", "#1E1B4B"]
        }
      ]
    }
    """
}
