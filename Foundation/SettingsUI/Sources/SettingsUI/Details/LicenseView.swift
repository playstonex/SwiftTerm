//
//  LicenseView.swift
//  SettingsUI
//
//  Created for GoodTerm
//

import SwiftUI

struct LicenseView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    private var macOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                Text(loadLicense())
                    .textSelection(.enabled)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 700, height: 500)
    }

    private var iOSBody: some View {
        ScrollView {
            Text(loadLicense())
                .textSelection(.enabled)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        #if os(iOS)
        .navigationTitle("License")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    func loadLicense() -> String {
        guard let bundle = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let str = try? String(contentsOfFile: bundle.path, encoding: .utf8)
        else {
            return "Failed to load license info."
        }
        return str
    }
}
