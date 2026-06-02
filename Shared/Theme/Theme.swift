//
//  Theme.swift
//  TelephoneBoothOperatorMobile
//
//  Catppuccin Latte (light) / Mocha (dark) palette for the operator app.
//  Booth-themed accent: soft-red maroon to echo Bell Canada signage.
//

import Foundation
import os
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum Theme {
    public enum IOSThemeMode: String, CaseIterable, Hashable, Identifiable, Sendable {
        case catppuccinAuto
        case catppuccinLight
        case catppuccinDark
        case systemAuto
        case systemLight
        case systemDark

        public static let defaultsKey = "TBOperatorIOSThemeMode"
        public static let defaultMode: IOSThemeMode = .catppuccinAuto

        private static let cachedMode = OSAllocatedUnfairLock<IOSThemeMode?>(initialState: nil)

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .catppuccinAuto: return "Catppuccin Auto"
            case .catppuccinLight: return "Catppuccin Light"
            case .catppuccinDark: return "Catppuccin Dark"
            case .systemAuto: return "System Default Auto"
            case .systemLight: return "System Default Light"
            case .systemDark: return "System Default Dark"
            }
        }

        public var preferredColorScheme: ColorScheme? {
            switch self {
            case .catppuccinAuto, .systemAuto: return nil
            case .catppuccinLight, .systemLight: return .light
            case .catppuccinDark, .systemDark: return .dark
            }
        }

        fileprivate var usesSystemPalette: Bool {
            switch self {
            case .systemAuto, .systemLight, .systemDark: return true
            case .catppuccinAuto, .catppuccinLight, .catppuccinDark: return false
            }
        }

        public static func storedMode(in defaults: UserDefaults = .standard) -> IOSThemeMode {
            if let cached = cachedMode.withLock({ $0 }) {
                return cached
            }
            let mode = readStoredMode(in: defaults)
            cachedMode.withLock { cached in
                cached = mode
            }
            return mode
        }

        public static func persist(_ mode: IOSThemeMode, in defaults: UserDefaults = .standard) {
            defaults.set(mode.rawValue, forKey: defaultsKey)
            cachedMode.withLock { cached in
                cached = mode
            }
        }

        private static func readStoredMode(in defaults: UserDefaults) -> IOSThemeMode {
            guard let stored = defaults.string(forKey: defaultsKey),
                  let mode = IOSThemeMode(rawValue: stored)
            else {
                return defaultMode
            }
            return mode
        }

        fileprivate static var current: IOSThemeMode {
            // Theme.swift is also built into the widget extension, which does
            // not include AppConfig. Reading the shared preference here keeps
            // SwiftUI dynamic colors self-contained across all iOS targets;
            // storedMode() caches after the first UserDefaults lookup.
            storedMode()
        }
    }

    fileprivate enum CatppuccinLatte {
        static let rosewater = Color(hex: "dc8a78")
        static let flamingo = Color(hex: "dd7878")
        static let pink = Color(hex: "ea76cb")
        static let mauve = Color(hex: "8839ef")
        static let red = Color(hex: "d20f39")
        static let maroon = Color(hex: "e64553")
        static let peach = Color(hex: "fe640b")
        static let yellow = Color(hex: "df8e1d")
        static let green = Color(hex: "40a02b")
        static let teal = Color(hex: "179299")
        static let sky = Color(hex: "04a5e5")
        static let sapphire = Color(hex: "209fb5")
        static let blue = Color(hex: "1e66f5")
        static let lavender = Color(hex: "7287fd")
        static let text = Color(hex: "4c4f69")
        static let subtext1 = Color(hex: "5c5f77")
        static let subtext0 = Color(hex: "6c6f85")
        static let overlay2 = Color(hex: "7c7f93")
        static let overlay1 = Color(hex: "8c8fa1")
        static let overlay0 = Color(hex: "9ca0b0")
        static let surface2 = Color(hex: "acb0be")
        static let surface1 = Color(hex: "bcc0cc")
        static let surface0 = Color(hex: "ccd0da")
        static let base = Color(hex: "eff1f5")
        static let mantle = Color(hex: "e6e9ef")
        static let crust = Color(hex: "dce0e8")
    }

    fileprivate enum CatppuccinMocha {
        static let rosewater = Color(hex: "f5e0dc")
        static let flamingo = Color(hex: "f2cdcd")
        static let pink = Color(hex: "f5c2e7")
        static let mauve = Color(hex: "cba6f7")
        static let red = Color(hex: "f38ba8")
        static let maroon = Color(hex: "eba0ac")
        static let peach = Color(hex: "fab387")
        static let yellow = Color(hex: "f9e2af")
        static let green = Color(hex: "a6e3a1")
        static let teal = Color(hex: "94e2d5")
        static let sky = Color(hex: "89dceb")
        static let sapphire = Color(hex: "74c7ec")
        static let blue = Color(hex: "89b4fa")
        static let lavender = Color(hex: "b4befe")
        static let text = Color(hex: "cdd6f4")
        static let subtext1 = Color(hex: "bac2de")
        static let subtext0 = Color(hex: "a6adc8")
        static let overlay2 = Color(hex: "9399b2")
        static let overlay1 = Color(hex: "7f849c")
        static let overlay0 = Color(hex: "6c7086")
        static let surface2 = Color(hex: "585b70")
        static let surface1 = Color(hex: "45475a")
        static let surface0 = Color(hex: "313244")
        static let base = Color(hex: "1e1e2e")
        static let mantle = Color(hex: "181825")
        static let crust = Color(hex: "11111b")
    }

    #if os(iOS)
    fileprivate static func dynamicColor(
        light: Color,
        dark: Color,
        system: @escaping (UIUserInterfaceStyle) -> UIColor
    ) -> Color {
        Color(UIColor { traitCollection in
            let mode = IOSThemeMode.current
            let interfaceStyle: UIUserInterfaceStyle
            switch mode {
            case .catppuccinLight, .systemLight:
                interfaceStyle = .light
            case .catppuccinDark, .systemDark:
                interfaceStyle = .dark
            case .catppuccinAuto, .systemAuto:
                interfaceStyle = traitCollection.userInterfaceStyle
            }

            if mode.usesSystemPalette {
                return system(interfaceStyle)
            }
            return interfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
    #else
    // Non-iOS platforms either keep their native palette (macOS / visionOS)
    // or use the fixed Catppuccin Mocha palette (watchOS / tvOS).
    fileprivate static func dynamicColor(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        #if os(watchOS) || os(tvOS)
        // watchOS and tvOS are intentionally dark-only in this app.
        return dark
        #else
        return Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #endif
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        }))
        #else
        return light
        #endif
    }
    #endif

    #if os(macOS) || os(visionOS)
    /// Tiers of system background used by the native (non-Catppuccin)
    /// macOS / visionOS palette.
    fileprivate enum BackgroundTier {
        case window
        case secondary
        case elevated
    }

    fileprivate static func systemBackground(_ tier: BackgroundTier) -> Color {
        #if os(macOS)
        switch tier {
        case .window:    return Color(nsColor: .windowBackgroundColor)
        case .secondary: return Color(nsColor: .underPageBackgroundColor)
        case .elevated:  return Color(nsColor: .controlBackgroundColor)
        }
        #else
        switch tier {
        case .window:    return Color(uiColor: .systemBackground)
        case .secondary: return Color(uiColor: .secondarySystemBackground)
        case .elevated:  return Color(uiColor: .tertiarySystemBackground)
        }
        #endif
    }
    #endif

    // macOS and visionOS deliberately use the platform's native light/dark
    // system palette (no Catppuccin) so the app feels at home on those
    // platforms. iOS / iPadOS can switch between the booth-flavoured
    // Catppuccin palette and native system colors, and the always-dark
    // platforms (watchOS / tvOS) keep Catppuccin Mocha.
    public enum Colors {
        #if os(macOS) || os(visionOS)
        public static let accent = Color.accentColor
        public static let primary = Color.accentColor
        public static let secondary = Color.orange

        public static let background = systemBackground(.window)
        public static let secondaryBackground = systemBackground(.secondary)
        public static let elevatedBackground = systemBackground(.elevated)

        public static let textPrimary = Color.primary
        public static let textSecondary = Color.secondary

        public static let error = Color.red
        public static let warning = Color.orange
        public static let success = Color.green
        public static let info = Color.blue
        #elseif os(iOS)
        public static var accent: Color {
            dynamicColor(
                light: CatppuccinLatte.maroon,
                dark: CatppuccinMocha.maroon,
                system: { _ in .systemBlue }
            )
        }

        public static var primary: Color {
            dynamicColor(
                light: CatppuccinLatte.red,
                dark: CatppuccinMocha.red,
                system: { _ in .systemBlue }
            )
        }

        public static var secondary: Color {
            dynamicColor(
                light: CatppuccinLatte.peach,
                dark: CatppuccinMocha.peach,
                system: { _ in .systemOrange }
            )
        }

        public static var background: Color {
            dynamicColor(
                light: CatppuccinLatte.base,
                dark: CatppuccinMocha.base,
                system: { _ in .systemBackground }
            )
        }

        public static var secondaryBackground: Color {
            dynamicColor(
                light: CatppuccinLatte.mantle,
                dark: CatppuccinMocha.mantle,
                system: { _ in .secondarySystemBackground }
            )
        }

        public static var elevatedBackground: Color {
            dynamicColor(
                light: CatppuccinLatte.surface0,
                dark: CatppuccinMocha.surface0,
                system: { _ in .tertiarySystemBackground }
            )
        }

        public static var textPrimary: Color {
            dynamicColor(
                light: CatppuccinLatte.text,
                dark: CatppuccinMocha.text,
                system: { _ in .label }
            )
        }

        public static var textSecondary: Color {
            dynamicColor(
                light: CatppuccinLatte.subtext0,
                dark: CatppuccinMocha.subtext0,
                system: { _ in .secondaryLabel }
            )
        }

        public static var error: Color {
            dynamicColor(
                light: CatppuccinLatte.red,
                dark: CatppuccinMocha.red,
                system: { _ in .systemRed }
            )
        }

        public static var warning: Color {
            dynamicColor(
                light: CatppuccinLatte.yellow,
                dark: CatppuccinMocha.yellow,
                system: { _ in .systemOrange }
            )
        }

        public static var success: Color {
            dynamicColor(
                light: CatppuccinLatte.green,
                dark: CatppuccinMocha.green,
                system: { _ in .systemGreen }
            )
        }

        public static var info: Color {
            dynamicColor(
                light: CatppuccinLatte.blue,
                dark: CatppuccinMocha.blue,
                system: { _ in .systemBlue }
            )
        }
        #else
        public static let accent = dynamicColor(light: CatppuccinLatte.maroon, dark: CatppuccinMocha.maroon)
        public static let primary = dynamicColor(light: CatppuccinLatte.red, dark: CatppuccinMocha.red)
        public static let secondary = dynamicColor(light: CatppuccinLatte.peach, dark: CatppuccinMocha.peach)

        public static let background = dynamicColor(light: CatppuccinLatte.base, dark: CatppuccinMocha.base)
        public static let secondaryBackground = dynamicColor(
            light: CatppuccinLatte.mantle,
            dark: CatppuccinMocha.mantle
        )
        public static let elevatedBackground = dynamicColor(
            light: CatppuccinLatte.surface0,
            dark: CatppuccinMocha.surface0
        )

        public static let textPrimary = dynamicColor(light: CatppuccinLatte.text, dark: CatppuccinMocha.text)
        public static let textSecondary = dynamicColor(
            light: CatppuccinLatte.subtext0,
            dark: CatppuccinMocha.subtext0
        )

        public static let error = dynamicColor(light: CatppuccinLatte.red, dark: CatppuccinMocha.red)
        public static let warning = dynamicColor(light: CatppuccinLatte.yellow, dark: CatppuccinMocha.yellow)
        public static let success = dynamicColor(light: CatppuccinLatte.green, dark: CatppuccinMocha.green)
        public static let info = dynamicColor(light: CatppuccinLatte.blue, dark: CatppuccinMocha.blue)
        #endif
    }

    public enum Fonts {
        public static func headerXL() -> Font {
            #if os(macOS)
            .system(size: 22, weight: .bold, design: .serif)
            #else
            .system(size: 36, weight: .bold, design: .serif)
            #endif
        }

        public static func headerLarge() -> Font {
            #if os(macOS)
            .system(size: 17, weight: .semibold, design: .serif)
            #else
            .system(size: 24, weight: .bold, design: .serif)
            #endif
        }

        #if os(macOS)
        public static let bodyLarge = Font.system(size: 15)
        public static let bodyMedium = Font.system(size: 13)
        public static let bodySmall = Font.system(size: 12)
        #else
        public static let bodyLarge = Font.system(size: 18)
        public static let bodyMedium = Font.system(size: 16)
        public static let bodySmall = Font.system(size: 14)
        #endif
        public static let caption = Font.caption
    }

    public enum Spacing {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let large: CGFloat = 16
        public static let extraLarge: CGFloat = 20
    }

    public static let cornerRadius: CGFloat = 12
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let alpha, red, green, blue: UInt64
        switch hex.count {
        case 3:
            (alpha, red, green, blue) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (alpha, red, green, blue) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (alpha, red, green, blue) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (alpha, red, green, blue) = (255, 0, 0, 0)
            assertionFailure("Invalid hex color string: \(hex)")
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}
