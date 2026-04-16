//
//  Interface.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/8.
//

import RayonModule
import SwiftUI

private var isBootstrapCompleted = false

struct MainView: View {
    @EnvironmentObject var store: RayonStore

    @State var openLicenseAgreementView: Bool = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
        } detail: {
            WelcomeView().requiresFrame()
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            openLicenseIfNeeded()
        }
        .sheet(isPresented: $openLicenseAgreementView) {
            openLicenseIfNeeded()
        } content: {
            AgreementView()
        }
        .overlay(
            Color.black
                .opacity(store.globalProgressInPresent ? 0.5 : 0)
                .overlay(
                    SheetTemplate.makeProgress(text: "Operation in progress")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusLarge))
                        .shadow(color: .black.opacity(0.15), radius: 16, y: 4)
                        .opacity(store.globalProgressInPresent ? 1 : 0)
                )
                .ignoresSafeArea()
        )
    }

    func openLicenseIfNeeded() {
        mainActor(delay: 0.5) {
            guard store.licenseAgreed else {
                openLicenseAgreementView = true
                return
            }
        }
    }
}
