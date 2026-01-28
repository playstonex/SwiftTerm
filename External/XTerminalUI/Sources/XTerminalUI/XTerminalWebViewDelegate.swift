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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let script = """
            (function() {
                try {
                    const terminal = window.M || window.term || window.terminal;
                    if (terminal && typeof terminal.attachCustomKeyEventHandler === 'function') {
                        terminal.attachCustomKeyEventHandler(function(e) {
                            // Check for Ctrl+C or Cmd+C when text is selected
                            if ((e.ctrlKey || e.metaKey) && e.key === 'c' && !e.shiftKey) {
                                // Get selection using multiple methods
                                let selection = null;
                                if (typeof terminal.hasSelection === 'function' && terminal.hasSelection()) {
                                    if (typeof terminal.getSelection === 'function') {
                                        selection = terminal.getSelection();
                                    } else if (terminal.selectionText) {
                                        selection = terminal.selectionText;
                                    }
                                }
                                if (selection && selection.length > 0) {
                                    e.preventDefault();
                                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.callbackHandler) {
                                        window.webkit.messageHandlers.callbackHandler.postMessage({
                                            magic: 'copy',
                                            msg: selection
                                        });
                                    }
                                }
                            }
                        });
                        console.log('Clipboard handler attached successfully');
                    } else {
                        console.log('Terminal or attachCustomKeyEventHandler not available');
                    }
                } catch (e) {
                    console.error('Error attaching clipboard handler:', e);
                }
            })();
            """
            view.evaluateJavaScript(script) { result, error in
                if let error = error {
                    debugPrint("Error enabling clipboard: \(error)")
                }
            }
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
