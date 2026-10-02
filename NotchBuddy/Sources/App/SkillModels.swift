import AppKit
import SwiftUI

// Models for the local "skill" pills: Music, Timer, System.
// Unlike the API integrations these need no key — they read what the Mac already knows.

// MARK: - Music

struct NowPlaying: Equatable {
    enum Player: String, CaseIterable {
        case spotify, music

        var bundleId: String {
            switch self {
            case .spotify: return "com.spotify.client"
            case .music:   return "com.apple.Music"
            }
        }
        var displayName: String {
            switch self {
            case .spotify: return "Spotify"
            case .music:   return "Music"
            }
        }
        var isRunning: Bool {
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
        }
        var isInstalled: Bool {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
        }
    }

    var player: Player
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var duration: TimeInterval      // seconds, 0 = unknown
    var position: TimeInterval      // seconds at `positionDate`
    var positionDate: Date
    var trackKey: String            // stable per track — drives artwork reloads
    var artwork: NSImage? = nil {
        didSet {
            palette = artwork.map(ArtworkPalette.colors) ?? []
            // Mochi wears a light tone of the cover while this track plays
            mochiTint = ArtworkPalette.pastel(of: palette)
        }
    }
    private(set) var palette: [Color] = []   // 3×3 grid of cover colours, drives the card's liquid backdrop
    private(set) var mochiTint: CGColor? = nil

    /// Playback position extrapolated from the last known reading.
    func position(at now: Date) -> TimeInterval {
        let p = isPlaying ? position + now.timeIntervalSince(positionDate) : position
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }
}

/// Reduces a cover to a 3×3 grid of colours (row-major, top-left first), tuned for a dark card.
enum ArtworkPalette {
    static func colors(from image: NSImage) -> [Color] {
        let side = 24, cell = side / 3
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }

        var result: [Color] = []
        for row in 0..<3 {
            for col in 0..<3 {
                var r = 0.0, g = 0.0, b = 0.0
                for y in 0..<cell {
                    for x in 0..<cell {
                        let i = ((row * cell + y) * side + col * cell + x) * 4
                        r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2])
                    }
                }
                let n = Double(cell * cell) * 255
                let color = NSColor(srgbRed: r / n, green: g / n, blue: b / n, alpha: 1)
                // Richer, never too bright (white text sits on top), and the four corners pushed
                // deep so even a single-colour cover gives the glass light and shadow to bend.
                let corner = row != 1 && col != 1
                let brightness = min(0.74, max(0.30, Double(color.brightnessComponent)))
                result.append(Color(hue: Double(color.hueComponent),
                                    saturation: min(1, Double(color.saturationComponent) * 1.35 + 0.08),
                                    brightness: corner ? brightness * 0.42 : brightness))
            }
        }
        return result
    }

    /// A soft, light version of the cover's most colourful tone — what Mochi wears while it plays.
    static func pastel(of palette: [Color]) -> CGColor? {
        guard !palette.isEmpty else { return nil }
        let colors = palette.compactMap { NSColor($0).usingColorSpace(.deviceRGB) }
        guard let vivid = colors.max(by: { $0.saturationComponent < $1.saturationComponent }) else { return nil }
        return NSColor(hue: vivid.hueComponent, saturation: min(0.42, vivid.saturationComponent * 0.6),
                       brightness: 0.97, alpha: 1).cgColor
    }
}

// MARK: - System

struct SystemStats: Equatable {
    var cpu: Double                 // 0…1, all cores
    var memUsed: UInt64             // bytes
    var memTotal: UInt64            // bytes
    var battery: Double?            // 0…1, nil on Macs without a battery
    var isCharging: Bool
    var onAC: Bool
    var minutesRemaining: Int?      // to empty on battery, to full while charging
    var cpuHot: Bool                // sustained high load
    var thermalWarning: Bool

    var memFraction: Double { memTotal > 0 ? Double(memUsed) / Double(memTotal) : 0 }
    var batteryLow: Bool { (battery ?? 1) <= 0.20 && !onAC }
}

// MARK: - Timer

struct Countdown: Identifiable, Equatable, Codable {
    enum Kind: String, Codable { case focus, rest, reminder }

    var id = UUID()
    var kind: Kind
    var label: String
    var total: TimeInterval
    var endDate: Date?                      // set while running
    var pausedRemaining: TimeInterval?      // set while paused
    var done = false

    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at now: Date) -> TimeInterval {
        if done { return 0 }
        if let p = pausedRemaining { return p }
        return max(0, (endDate ?? now).timeIntervalSince(now))
    }

    func progress(at now: Date) -> Double {
        total > 0 ? min(1, max(0, 1 - remaining(at: now) / total)) : 1
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "12m", "1h 05m", "45s" — for secondary rows.
    static func short(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(Int((Double(s) / 60).rounded(.up)))m" }
        return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
    }
}

// MARK: - Dynamic-Island toast

/// A short banner that drops from the notch (track change, file parked…).
struct IslandToast: Equatable {
    var id = UUID()
    var artwork: NSImage? = nil
    var symbol: String? = nil        // SF Symbol when there is no artwork
    var title: String
    var subtitle: String
    var palette: [Color] = []        // backdrop colours (9); empty → grown from `accent`
    var accent: String = "#818CF8"
    var focusId: String? = nil       // pill opened when the banner is clicked
    var showsEqualizer = false
    var battery: Double? = nil       // power banner: charge level 0…1, drawn as a filling battery
    var charging = false
    var hud: HUDKind? = nil          // volume / brightness slider instead of text
    var level: Double = 0            // slider position 0…1
    var muted = false
    var action: ToastAction? = nil   // button on the right of the banner
}

enum HUDKind: Equatable { case volume, brightness }

enum ToastAction: Equatable {
    case jump(taskId: String)        // bring the terminal running this Claude Code session forward
}

// MARK: - Notes

struct NoteItem: Identifiable, Equatable, Codable {
    var id = UUID()
    var text: String
    var date: Date
    var done = false
}

// MARK: - Weather

struct WeatherInfo: Equatable {
    struct Hour: Equatable, Identifiable {
        var date: Date
        var temp: Double
        var code: Int
        var isDay: Bool
        var id: Date { date }
    }

    var city: String
    var temp: Double
    var code: Int                    // WMO weather code
    var isDay: Bool
    var high: Double
    var low: Double
    var hours: [Hour]                // the next few hours
    var fetched: Date

    enum Kind { case clear, cloudy, fog, rain, snow, storm }

    var isCold = false               // at or below 2 °C
    var unit = "C"

    var kind: Kind { Self.kind(of: code) }

    static func kind(of code: Int) -> Kind {
        switch code {
        case 0, 1:                      return .clear
        case 2, 3:                      return .cloudy
        case 45, 48:                    return .fog
        case 51...67, 80...82:          return .rain
        case 71...77, 85, 86:           return .snow
        case 95...99:                   return .storm
        default:                        return .cloudy
        }
    }

    static func symbol(code: Int, isDay: Bool) -> String {
        switch kind(of: code) {
        case .clear:  return isDay ? (code == 0 ? "sun.max.fill" : "sun.min.fill") : "moon.stars.fill"
        case .cloudy: return code == 2 ? (isDay ? "cloud.sun.fill" : "cloud.moon.fill") : "cloud.fill"
        case .fog:    return "cloud.fog.fill"
        case .rain:   return code >= 80 ? "cloud.heavyrain.fill" : (code < 60 ? "cloud.drizzle.fill" : "cloud.rain.fill")
        case .snow:   return "cloud.snow.fill"
        case .storm:  return "cloud.bolt.rain.fill"
        }
    }

    static func label(code: Int, isDay: Bool) -> String {
        switch kind(of: code) {
        case .clear:  return isDay ? "Sunny" : "Clear"
        case .cloudy: return code == 2 ? "Partly cloudy" : "Cloudy"
        case .fog:    return "Foggy"
        case .rain:   return code < 60 ? "Drizzle" : (code >= 80 ? "Showers" : "Rain")
        case .snow:   return "Snow"
        case .storm:  return "Thunderstorm"
        }
    }

    /// Accent for the card and the island's colour flow.
    var accent: String {
        switch kind {
        case .clear:  return isDay ? "#FBBF24" : "#818CF8"
        case .cloudy: return "#94A3B8"
        case .fog:    return "#A1A1AA"
        case .rain:   return "#38BDF8"
        case .snow:   return "#BAE6FD"
        case .storm:  return "#A78BFA"
        }
    }
}

// MARK: - Claude hub

/// Share of the Claude plan limits already used.
struct ClaudeUsage: Equatable {
    var fiveHour: Double             // 0…1
    var sevenDay: Double             // 0…1
    var fiveHourResets: Date? = nil
    var asOf: Date
}

/// A Claude Code session found in ~/.claude/projects.
struct ClaudeSession: Identifiable, Equatable {
    let id: String                   // session id (resume key)
    var title: String
    var cwd: String
    var modified: Date
    var livePid: Int32? = nil        // a running `claude` process owns it right now
    var busy = false

    /// Folder name — also for sessions carried over from Windows ("C:\\Users\\…\\Project").
    var project: String {
        cwd.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
    }
    var timeAgo: String {
        let diff = Date().timeIntervalSince(modified)
        if diff < 60    { return "now" }
        if diff < 3600  { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        return "\(Int(diff / 86400))d"
    }
}

// MARK: - Shelf & clipboard

struct ShelfItem: Identifiable, Equatable {
    var id: String { url.path }
    let url: URL
    var name: String { url.lastPathComponent }
}

struct ClipItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let date: Date
    var isLink: Bool { text.hasPrefix("http://") || text.hasPrefix("https://") }
    /// First non-empty line, for the one-line row.
    var preview: String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.trimmingCharacters(in: .whitespaces)
    }
}
