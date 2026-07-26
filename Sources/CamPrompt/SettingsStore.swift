import SwiftUI
import AppKit

/// All user-tunable prompter/camera settings, persisted to UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    private let d = UserDefaults.standard

    // MARK: Text appearance
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize") } }
    @Published var fontName: String { didSet { d.set(fontName, forKey: "fontName") } }
    @Published var isBold: Bool { didSet { d.set(isBold, forKey: "isBold") } }
    @Published var textColorHex: String { didSet { d.set(textColorHex, forKey: "textColorHex") } }
    @Published var bgColorHex: String { didSet { d.set(bgColorHex, forKey: "bgColorHex") } }
    @Published var bgOpacity: Double { didSet { d.set(bgOpacity, forKey: "bgOpacity") } }
    @Published var lineSpacing: Double { didSet { d.set(lineSpacing, forKey: "lineSpacing") } }
    @Published var horizontalMargin: Double { didSet { d.set(horizontalMargin, forKey: "horizontalMargin") } }
    @Published var alignment: Int { didSet { d.set(alignment, forKey: "alignment") } } // 0 left 1 center 2 right

    // MARK: Prompter behavior
    @Published var speed: Double { didSet { d.set(speed, forKey: "speed") } } // 1...100
    @Published var mirrorHorizontal: Bool { didSet { d.set(mirrorHorizontal, forKey: "mirrorHorizontal") } }
    @Published var mirrorVertical: Bool { didSet { d.set(mirrorVertical, forKey: "mirrorVertical") } }
    @Published var loopMode: Bool { didSet { d.set(loopMode, forKey: "loopMode") } }
    @Published var countdownSeconds: Int { didSet { d.set(countdownSeconds, forKey: "countdownSeconds") } }
    @Published var showPanelOnRecord: Bool { didSet { d.set(showPanelOnRecord, forKey: "showPanelOnRecord") } }

    // MARK: Panel geometry / behavior
    @Published var panelWidth: Double { didSet { d.set(panelWidth, forKey: "panelWidth") } }
    @Published var panelTextHeight: Double { didSet { d.set(panelTextHeight, forKey: "panelTextHeight") } }
    @Published var panelPinnedToNotch: Bool { didSet { d.set(panelPinnedToNotch, forKey: "panelPinnedToNotch") } }
    @Published var hideFromScreenCapture: Bool { didSet { d.set(hideFromScreenCapture, forKey: "hideFromScreenCapture") } }
    @Published var anchorFraction: Double { didSet { d.set(anchorFraction, forKey: "anchorFraction") } } // reading line position 0..1

    // MARK: Camera
    @Published var mirrorPreview: Bool { didSet { d.set(mirrorPreview, forKey: "mirrorPreview") } }
    @Published var selectedCameraID: String { didSet { d.set(selectedCameraID, forKey: "selectedCameraID") } }
    @Published var selectedMicID: String { didSet { d.set(selectedMicID, forKey: "selectedMicID") } }
    @Published var overlayTextOnPreview: Bool { didSet { d.set(overlayTextOnPreview, forKey: "overlayTextOnPreview") } }
    /// "downloads" | "documents" | "movies"
    @Published var recordingsFolder: String { didSet { d.set(recordingsFolder, forKey: "recordingsFolder") } }

    init() {
        func dbl(_ key: String, _ def: Double) -> Double {
            UserDefaults.standard.object(forKey: key) as? Double ?? def
        }
        func str(_ key: String, _ def: String) -> String {
            UserDefaults.standard.string(forKey: key) ?? def
        }
        func bool(_ key: String, _ def: Bool) -> Bool {
            UserDefaults.standard.object(forKey: key) as? Bool ?? def
        }
        func int(_ key: String, _ def: Int) -> Int {
            UserDefaults.standard.object(forKey: key) as? Int ?? def
        }
        fontSize = dbl("fontSize", 34)
        fontName = str("fontName", "System")
        isBold = bool("isBold", true)
        textColorHex = str("textColorHex", "#FFFFFF")
        bgColorHex = str("bgColorHex", "#000000")
        bgOpacity = dbl("bgOpacity", 0.85)
        lineSpacing = dbl("lineSpacing", 8)
        horizontalMargin = dbl("horizontalMargin", 24)
        alignment = int("alignment", 1)
        speed = dbl("speed", 20)
        mirrorHorizontal = bool("mirrorHorizontal", false)
        mirrorVertical = bool("mirrorVertical", false)
        loopMode = bool("loopMode", false)
        countdownSeconds = int("countdownSeconds", 3)
        showPanelOnRecord = bool("showPanelOnRecord", true)
        panelWidth = dbl("panelWidth", 700)
        panelTextHeight = dbl("panelTextHeight", 190)
        panelPinnedToNotch = bool("panelPinnedToNotch", true)
        hideFromScreenCapture = bool("hideFromScreenCapture", false)
        anchorFraction = dbl("anchorFraction", 0.22)
        mirrorPreview = bool("mirrorPreview", true)
        selectedCameraID = str("selectedCameraID", "")
        selectedMicID = str("selectedMicID", "")
        overlayTextOnPreview = bool("overlayTextOnPreview", false)
        recordingsFolder = str("recordingsFolder", "downloads")
    }

    /// Points per second derived from the 1...100 speed knob.
    var pointsPerSecond: Double { speed * 3.0 }

    var textAlignment: TextAlignment {
        switch alignment {
        case 0: return .leading
        case 2: return .trailing
        default: return .center
        }
    }

    var frameAlignment: Alignment {
        switch alignment {
        case 0: return .leading
        case 2: return .trailing
        default: return .center
        }
    }

    func font() -> Font {
        if fontName == "System" {
            return .system(size: fontSize, weight: isBold ? .bold : .regular)
        }
        var f = Font.custom(fontName, size: fontSize)
        if isBold { f = f.bold() }
        return f
    }

    static let availableFonts: [String] = [
        "System", "Helvetica Neue", "Arial", "Georgia", "Avenir Next",
        "Times New Roman", "Menlo", "Verdana", "Charter", "PT Sans", "PT Serif"
    ]
}

// MARK: - Hex color helpers

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        Scanner(string: hexString).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
