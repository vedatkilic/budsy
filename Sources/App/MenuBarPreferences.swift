import Foundation

/// What the menu-bar item shows next to its glyph while earbuds are connected.
/// `lowest` is the original behaviour, so it is the default.
enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case iconOnly, lowest, both, withCase

    var id: String { rawValue }

    /// Catalogue key; wrap in `LocalizedStringKey` to display.
    var title: String {
        switch self {
        case .iconOnly: "Icon only"
        case .lowest: "Lowest battery"
        case .both: "Both earbuds"
        case .withCase: "Earbuds and case"
        }
    }
}

/// The user's menu-bar choices, kept in `UserDefaults` so the status item can
/// re-read them whenever `UserDefaults.didChangeNotification` fires.
enum MenuBarPreferences {
    private static let displayKey = "menuBarDisplay"
    private static let hidesKey = "hideMenuBarIconWhenDisconnected"

    static var display: MenuBarDisplay {
        get {
            UserDefaults.standard.string(forKey: displayKey)
                .flatMap(MenuBarDisplay.init(rawValue:)) ?? .lowest
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: displayKey) }
    }

    /// Opt-in: off by default, so the icon stays put unless the user asks.
    static var hidesWhenDisconnected: Bool {
        get { UserDefaults.standard.bool(forKey: hidesKey) }
        set { UserDefaults.standard.set(newValue, forKey: hidesKey) }
    }
}
