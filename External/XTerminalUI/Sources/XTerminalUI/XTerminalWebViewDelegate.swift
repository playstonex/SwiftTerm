//
//  TerminalWebViewDelegate.swift
//
//
//  Created by Lakr Aream on 2022/2/6.
//

import Foundation
import WebKit

class XTerminalWebViewDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var userContentController: WKUserContentController?

    var navigateCompleted: Bool = false
    var onNavigationCompleted: (() -> Void)?

    func webView(_ view: WKWebView, didFinish _: WKNavigation!) {
        debugPrint("\(self) \(#function)")
        navigateCompleted = true

        #if os(macOS)
            enableSearch(view: view)
        #endif

        #if os(iOS)
            enableClipboard(view: view)
        #endif

        onNavigationCompleted?()
    }

    func enableClipboard(view: WKWebView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let script = """
            (function() {
                const terminal = window.M || window.term || window.terminal;
                if (terminal) {
                    terminal.attachCustomKeyEventHandler(function(e) {
                        // Check for Ctrl+C or Cmd+C when text is selected
                        if ((e.ctrlKey || e.metaKey) && e.key === 'c' && !e.shiftKey) {
                            const selection = terminal.selectionText;
                            if (selection && selection.length > 0) {
                                e.preventDefault();
                                window.webkit.messageHandlers.callbackHandler.postMessage({
                                    magic: 'copy',
                                    msg: selection
                                });
                            }
                        }
                    });
                }
            })();
            """
            view.evaluateJavaScript(script, completionHandler: nil)
        }
    }
    
    func enableSearch(view: WKWebView) {
        DispatchQueue.global().async {
            let script = "window.manager.enableFeature(\"searchBar\")"
            view.evaluateJavascriptWithRetry(javascript: script)
        }
    }

    deinit {
        // webkit's bug, still holding ref after deinit
        // the buffer chain will that holds a retain to shell
        // to fool the release logic for disconnect and cleanup
        debugPrint("\(self) __deinit__")
        if Thread.isMainThread {
            userContentController?.removeScriptMessageHandler(forName: "callbackHandler")
        } else {
            let sem = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { [self] in
                defer { sem.signal() }
                self.userContentController?.removeScriptMessageHandler(forName: "callbackHandler")
            }
            sem.wait()
        }
    }
}
