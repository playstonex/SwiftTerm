//
//  TerminalTheme.swift
//  Rayon
//
//  Terminal color themes
//

import Foundation

public struct TerminalTheme: Codable, Equatable {
    public let name: String
    public let foreground: String
    public let background: String
    public let cursor: String
    public let black: String
    public let red: String
    public let green: String
    public let yellow: String
    public let blue: String
    public let magenta: String
    public let cyan: String
    public let white: String
    public let brightBlack: String
    public let brightRed: String
    public let brightGreen: String
    public let brightYellow: String
    public let brightBlue: String
    public let brightMagenta: String
    public let brightCyan: String
    public let brightWhite: String

    public init(
        name: String,
        foreground: String,
        background: String,
        cursor: String,
        black: String,
        red: String,
        green: String,
        yellow: String,
        blue: String,
        magenta: String,
        cyan: String,
        white: String,
        brightBlack: String,
        brightRed: String,
        brightGreen: String,
        brightYellow: String,
        brightBlue: String,
        brightMagenta: String,
        brightCyan: String,
        brightWhite: String
    ) {
        self.name = name
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.black = black
        self.red = red
        self.green = green
        self.yellow = yellow
        self.blue = blue
        self.magenta = magenta
        self.cyan = cyan
        self.white = white
        self.brightBlack = brightBlack
        self.brightRed = brightRed
        self.brightGreen = brightGreen
        self.brightYellow = brightYellow
        self.brightBlue = brightBlue
        self.brightMagenta = brightMagenta
        self.brightCyan = brightCyan
        self.brightWhite = brightWhite
    }

    public static let `default` = TerminalTheme(
        name: "Default",
        foreground: "#ffffff",
        background: "#000000",
        cursor: "#ffffff",
        black: "#000000",
        red: "#cd3131",
        green: "#0dbc79",
        yellow: "#e5e510",
        blue: "#2472c8",
        magenta: "#bc3fbc",
        cyan: "#11a8cd",
        white: "#e5e5e5",
        brightBlack: "#666666",
        brightRed: "#f14c4c",
        brightGreen: "#23d18b",
        brightYellow: "#f5f543",
        brightBlue: "#3b8eea",
        brightMagenta: "#d670d6",
        brightCyan: "#29b8db",
        brightWhite: "#ffffff"
    )

    public static let solarizedDark = TerminalTheme(
        name: "Solarized Dark",
        foreground: "#839496",
        background: "#002b36",
        cursor: "#839496",
        black: "#073642",
        red: "#dc322f",
        green: "#859900",
        yellow: "#b58900",
        blue: "#268bd2",
        magenta: "#d33682",
        cyan: "#2aa198",
        white: "#eee8d5",
        brightBlack: "#002b36",
        brightRed: "#cb4b16",
        brightGreen: "#586e75",
        brightYellow: "#657b83",
        brightBlue: "#839496",
        brightMagenta: "#6c71c4",
        brightCyan: "#93a1a1",
        brightWhite: "#fdf6e3"
    )

    public static let solarizedLight = TerminalTheme(
        name: "Solarized Light",
        foreground: "#657b83",
        background: "#fdf6e3",
        cursor: "#657b83",
        black: "#073642",
        red: "#dc322f",
        green: "#859900",
        yellow: "#b58900",
        blue: "#268bd2",
        magenta: "#d33682",
        cyan: "#2aa198",
        white: "#eee8d5",
        brightBlack: "#002b36",
        brightRed: "#cb4b16",
        brightGreen: "#586e75",
        brightYellow: "#657b83",
        brightBlue: "#839496",
        brightMagenta: "#6c71c4",
        brightCyan: "#93a1a1",
        brightWhite: "#fdf6e3"
    )

    public static let dracula = TerminalTheme(
        name: "Dracula",
        foreground: "#f8f8f2",
        background: "#282a36",
        cursor: "#f8f8f2",
        black: "#000000",
        red: "#ff5555",
        green: "#50fa7b",
        yellow: "#f1fa8c",
        blue: "#bd93f9",
        magenta: "#ff79c6",
        cyan: "#8be9fd",
        white: "#bfbfbf",
        brightBlack: "#4d4d4d",
        brightRed: "#ff6e67",
        brightGreen: "#5af78e",
        brightYellow: "#f4f99d",
        brightBlue: "#caa9fa",
        brightMagenta: "#ff92d0",
        brightCyan: "#9aedfe",
        brightWhite: "#e6e6e6"
    )

    public static let nord = TerminalTheme(
        name: "Nord",
        foreground: "#d8dee9",
        background: "#2e3440",
        cursor: "#d8dee9",
        black: "#3b4252",
        red: "#bf616a",
        green: "#a3be8c",
        yellow: "#ebcb8b",
        blue: "#81a1c1",
        magenta: "#b48ead",
        cyan: "#88c0d0",
        white: "#e5e9f0",
        brightBlack: "#4c566a",
        brightRed: "#bf616a",
        brightGreen: "#a3be8c",
        brightYellow: "#ebcb8b",
        brightBlue: "#81a1c1",
        brightMagenta: "#b48ead",
        brightCyan: "#8fbcbb",
        brightWhite: "#eceff4"
    )

    public static let tokyoNight = TerminalTheme(
        name: "Tokyo Night",
        foreground: "#c0caf5",
        background: "#1a1b26",
        cursor: "#c0caf5",
        black: "#15161e",
        red: "#f7768e",
        green: "#9ece6a",
        yellow: "#e0af68",
        blue: "#7aa2f7",
        magenta: "#bb9af7",
        cyan: "#7dcfff",
        white: "#a9b1d6",
        brightBlack: "#414868",
        brightRed: "#f7768e",
        brightGreen: "#9ece6a",
        brightYellow: "#e0af68",
        brightBlue: "#7aa2f7",
        brightMagenta: "#bb9af7",
        brightCyan: "#7dcfff",
        brightWhite: "#c0caf5"
    )

    public static let tokyoNightDay = TerminalTheme(
        name: "Tokyo Night Day",
        foreground: "#3760bf",
        background: "#e1e2e7",
        cursor: "#3760bf",
        black: "#b4b5b9",
        red: "#f52a65",
        green: "#587539",
        yellow: "#8c6c3e",
        blue: "#2e7de9",
        magenta: "#9854f1",
        cyan: "#007197",
        white: "#6172b0",
        brightBlack: "#a1a6c5",
        brightRed: "#f52a65",
        brightGreen: "#587539",
        brightYellow: "#8c6c3e",
        brightBlue: "#2e7de9",
        brightMagenta: "#9854f1",
        brightCyan: "#007197",
        brightWhite: "#3760bf"
    )

    public static let monokai = TerminalTheme(
        name: "Monokai",
        foreground: "#f8f8f2",
        background: "#272822",
        cursor: "#f8f8f2",
        black: "#272822",
        red: "#f92672",
        green: "#a6e22e",
        yellow: "#f4bf75",
        blue: "#66d9ef",
        magenta: "#ae81ff",
        cyan: "#a1efe4",
        white: "#f8f8f2",
        brightBlack: "#75715e",
        brightRed: "#f92672",
        brightGreen: "#a6e22e",
        brightYellow: "#f4bf75",
        brightBlue: "#66d9ef",
        brightMagenta: "#ae81ff",
        brightCyan: "#a1efe4",
        brightWhite: "#f9f8f5"
    )

    // MARK: - Custom Themes

    private static let customThemesKey = "wiki.qaq.rayon.customTerminalThemes"

    public static var customThemes: [TerminalTheme] {
        get {
            guard let data = UserDefaults.standard.data(forKey: customThemesKey) else { return [] }
            return (try? JSONDecoder().decode([TerminalTheme].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: customThemesKey)
        }
    }

    public static func addCustomTheme(_ theme: TerminalTheme) {
        var themes = customThemes
        // Replace if a theme with the same name exists
        if let index = themes.firstIndex(where: { $0.name == theme.name }) {
            themes[index] = theme
        } else {
            themes.append(theme)
        }
        customThemes = themes
    }

    public static func removeCustomTheme(named name: String) {
        customThemes = customThemes.filter { $0.name != name }
    }

    // MARK: - All Themes

    public static let builtInThemes: [TerminalTheme] = [
        .default, .solarizedDark, .solarizedLight, .dracula, .nord, .tokyoNight, .tokyoNightDay, .monokai
    ]

    public static var allThemes: [TerminalTheme] {
        builtInThemes + customThemes
    }

    // MARK: - iTerm2 Import

    public enum ImportError: Error, LocalizedError {
        case invalidFormat
        case fileAccessError

        public var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Invalid iTerm2 color scheme format"
            case .fileAccessError:
                return "Unable to access the color scheme file"
            }
        }
    }

    /// Import a terminal theme from an iTerm2 `.itermcolors` file.
    public static func fromItermColor(url: URL, name: String? = nil) throws -> TerminalTheme {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: [String: Any]] else {
            throw ImportError.invalidFormat
        }

        func hexColor(key: String) -> String {
            guard let dict = plist[key],
                  let r = dict["Red Component"] as? Double,
                  let g = dict["Green Component"] as? Double,
                  let b = dict["Blue Component"] as? Double else {
                return "#000000"
            }
            return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
        }

        let themeName = name ?? url.deletingPathExtension().lastPathComponent

        return TerminalTheme(
            name: themeName,
            foreground: hexColor(key: "Foreground Color"),
            background: hexColor(key: "Background Color"),
            cursor: hexColor(key: "Cursor Color"),
            black: hexColor(key: "Ansi 0 Color"),
            red: hexColor(key: "Ansi 1 Color"),
            green: hexColor(key: "Ansi 2 Color"),
            yellow: hexColor(key: "Ansi 3 Color"),
            blue: hexColor(key: "Ansi 4 Color"),
            magenta: hexColor(key: "Ansi 5 Color"),
            cyan: hexColor(key: "Ansi 6 Color"),
            white: hexColor(key: "Ansi 7 Color"),
            brightBlack: hexColor(key: "Ansi 8 Color"),
            brightRed: hexColor(key: "Ansi 9 Color"),
            brightGreen: hexColor(key: "Ansi 10 Color"),
            brightYellow: hexColor(key: "Ansi 11 Color"),
            brightBlue: hexColor(key: "Ansi 12 Color"),
            brightMagenta: hexColor(key: "Ansi 13 Color"),
            brightCyan: hexColor(key: "Ansi 14 Color"),
            brightWhite: hexColor(key: "Ansi 15 Color")
        )
    }
}
