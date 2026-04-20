//
//  mRayonApp.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//

import CodeEditorUI
import DataSync
import RayonModule
import SwiftUI
import SwiftTerminal
import RevenueCat


@main
struct mRayonApp: App {
    @StateObject private var store = RayonStore.shared

    init() {
        #if DEBUG
            NSLog("\nCommand Arguments:\n" + CommandLine.arguments.joined(separator: "\n"))
        #endif

        Purchases.configure(withAPIKey: "appl_VwjwBtwnKAECZPoUJvvJRNQTfhZ")
        
        _ = LogRedirect.shared
        _ = RayonStore.shared
        _ = SessionLifecycleCoordinator.shared

        SessionLifecycleCoordinator.shared.scheduleNextAppRefresh()

        AutomationManager.shared.startScheduler()
        NSLog("static main completed")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(
                    store.themePreference == "dark" ? .dark :
                    store.themePreference == "light" ? .light :
                    nil
                )
                .onAppear {
                    // Trigger automatic sync on app launch
                    Task {
                        await AutoSyncManager.shared.syncOnAppLaunch()
                    }

                    // optimize later on flight exp
                    let editor = SCodeEditor()
                    let xterm = STerminalView()
//                    checkAgreement()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        withExtendedLifetime(editor) {
                            debugPrint("editor \(editor) prewarm done")
                        }
                        withExtendedLifetime(xterm) {
                            debugPrint("xterm \(xterm) prewarm done")
                        }
                    }
                }
                .onChange(of: store.licenseAgreed) { _, _ in
                    checkAgreement()
                }

        }
    }

    func checkAgreement() {
        guard !store.licenseAgreed else {
            return
        }
        let host = UIHostingController(rootView: AgreementView())
        host.preferredContentSize = preferredPopOverSize
        host.isModalInPresentation = true
        host.modalTransitionStyle = .coverVertical
        host.modalPresentationStyle = .formSheet
        mainActor(delay: 0.5) {
            UIWindow.shutUpKeyWindow?
                .topMostViewController?
                .present(next: host)
        }
    }
}
