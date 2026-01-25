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

    public static let allThemes: [TerminalTheme] = [
        .default, .solarizedDark, .solarizedLight, .dracula, .nord, .tokyoNight, .monokai
    ]
}
