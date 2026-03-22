#if os(macOS) && canImport(SwiftUI)
import Foundation
import SwiftUI

/// A SwiftUI wrapper for ``LocalProcessTerminalView`` that launches a local shell on macOS.
public struct SwiftUILocalProcessTerminalView: NSViewRepresentable {
    public typealias NSViewType = LocalProcessTerminalView

    private let executable: String?
    private let args: [String]
    private let environment: [String]?
    private let execName: String?
    private let currentDirectory: String?
    private let configure: ((LocalProcessTerminalView) -> Void)?

    /// Creates a SwiftUI terminal view backed by ``LocalProcessTerminalView``.
    ///
    /// If `executable` is `nil`, the user's `SHELL` environment variable is used, falling back to `/bin/bash`.
    /// The default `args` value launches the shell as a login shell.
    public init(
        executable: String? = nil,
        args: [String] = ["-l"],
        environment: [String]? = nil,
        execName: String? = nil,
        currentDirectory: String? = nil,
        configure: ((LocalProcessTerminalView) -> Void)? = nil
    ) {
        self.executable = executable
        self.args = args
        self.environment = environment
        self.execName = execName
        self.currentDirectory = currentDirectory
        self.configure = configure
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        configure?(view)
        view.startProcess(
            executable: executable ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash",
            args: args,
            environment: environment,
            execName: execName,
            currentDirectory: currentDirectory
        )
        return view
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
    }

    public static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: ()) {
        nsView.terminate()
    }
}
#endif
