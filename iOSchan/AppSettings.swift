import Combine
import SwiftUI

enum ContentScale: String, CaseIterable, Identifiable, Hashable {
    case extraSmall
    case small
    case normal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extraSmall: return "Extra Small"
        case .small: return "Small"
        case .normal: return "Normal"
        }
    }

    var factor: CGFloat {
        switch self {
        case .extraSmall: return 0.6
        case .small: return 0.8
        case .normal: return 1.0
        }
    }
}

enum AppColorScheme: String, CaseIterable, Identifiable, Hashable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var scale: ContentScale {
        didSet { UserDefaults.standard.set(scale.rawValue, forKey: "contentScale") }
    }

    var uiScale: CGFloat { scale.factor }

    var dynamicType: DynamicTypeSize {
        switch scale {
        case .extraSmall: return .xSmall
        case .small: return .small
        case .normal: return .medium
        }
    }

    var scaleIndex: Int {
        get { ContentScale.allCases.firstIndex(of: scale) ?? 2 }
        set {
            let all = ContentScale.allCases
            if newValue >= 0 && newValue < all.count {
                scale = all[newValue]
            }
        }
    }

    enum Density: String, CaseIterable, Identifiable, Hashable {
        case compact, comfortable, roomy
        var id: String { rawValue }
        var title: String {
            switch self {
            case .compact: return "Compact"
            case .comfortable: return "Comfortable"
            case .roomy: return "Roomy"
            }
        }
        var spacingMultiplier: CGFloat {
            switch self {
            case .compact: return 0.8
            case .comfortable: return 1.0
            case .roomy: return 1.2
            }
        }
    }

    @Published var showFlags: Bool {
        didSet { UserDefaults.standard.set(showFlags, forKey: "showFlags") }
    }
    @Published var showIDs: Bool {
        didSet { UserDefaults.standard.set(showIDs, forKey: "showIDs") }
    }
    @Published var showReplyCounts: Bool {
        didSet { UserDefaults.standard.set(showReplyCounts, forKey: "showReplyCounts") }
    }
    @Published var showImageCounts: Bool {
        didSet { UserDefaults.standard.set(showImageCounts, forKey: "showImageCounts") }
    }
    @Published var highlightOP: Bool {
        didSet { UserDefaults.standard.set(highlightOP, forKey: "highlightOP") }
    }
    @Published var density: Density {
        didSet { UserDefaults.standard.set(density.rawValue, forKey: "density") }
    }
    var densityIndex: Int {
        get { Density.allCases.firstIndex(of: density) ?? 1 }
        set {
            let all = Density.allCases
            if newValue >= 0 && newValue < all.count {
                density = all[newValue]
            }
        }
    }
    @Published var thumbnailScale: CGFloat {
        didSet { UserDefaults.standard.set(Double(thumbnailScale), forKey: "thumbnailScale") }
    }
    @Published var fontFineTune: CGFloat {
        didSet { UserDefaults.standard.set(Double(fontFineTune), forKey: "fontFineTune") }
    }

    @Published var colorScheme: AppColorScheme {
        didSet { UserDefaults.standard.set(colorScheme.rawValue, forKey: "appColorScheme") }
    }

    var preferredColorScheme: ColorScheme? {
        switch colorScheme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var adjustedDynamicType: DynamicTypeSize {
        let base = dynamicType
        if fontFineTune <= -0.34 { return base.smaller() }
        if fontFineTune >= 0.34 { return base.larger() }
        return base
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: "contentScale"),
           let saved = ContentScale(rawValue: raw) {
            self.scale = saved
        } else {
            self.scale = .normal
        }

        self.showFlags = UserDefaults.standard.object(forKey: "showFlags") as? Bool ?? true
        self.showIDs = UserDefaults.standard.object(forKey: "showIDs") as? Bool ?? true
        self.showReplyCounts = UserDefaults.standard.object(forKey: "showReplyCounts") as? Bool ?? true
        self.showImageCounts = UserDefaults.standard.object(forKey: "showImageCounts") as? Bool ?? true
        self.highlightOP = UserDefaults.standard.object(forKey: "highlightOP") as? Bool ?? true
        if let rawDensity = UserDefaults.standard.string(forKey: "density"), let d = Density(rawValue: rawDensity) {
            self.density = d
        } else {
            self.density = .comfortable
        }
        let ts = UserDefaults.standard.object(forKey: "thumbnailScale") as? Double ?? 1.0
        self.thumbnailScale = CGFloat(ts)
        let ff = UserDefaults.standard.object(forKey: "fontFineTune") as? Double ?? 0.0
        self.fontFineTune = CGFloat(ff)

        if let rawCS = UserDefaults.standard.string(forKey: "appColorScheme"),
           let savedCS = AppColorScheme(rawValue: rawCS) {
            self.colorScheme = savedCS
        } else {
            self.colorScheme = .system
        }
    }
}

extension DynamicTypeSize {
    func larger() -> DynamicTypeSize {
        switch self {
        case .xSmall: return .small
        case .small: return .medium
        case .medium: return .large
        case .large: return .xLarge
        case .xLarge: return .xxLarge
        case .xxLarge: return .xxxLarge
        default: return self
        }
    }
    func smaller() -> DynamicTypeSize {
        switch self {
        case .xxxLarge: return .xxLarge
        case .xxLarge: return .xLarge
        case .xLarge: return .large
        case .large: return .medium
        case .medium: return .small
        case .small: return .xSmall
        default: return self
        }
    }
}
