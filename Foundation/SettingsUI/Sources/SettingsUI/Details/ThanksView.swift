//
//  ThanksView.swift
//  SettingsUI
//
//  Created for GoodTerm
//

import Colorful
import SwiftUI

struct ThanksView: View {
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
                sheetBody
            }
        }
        .frame(width: 600, height: 350)
    }

    private var iOSBody: some View {
        ScrollView {
            sheetBody
        }
        .background(
            ColorfulView(
                colors: [Color.accentColor],
                colorCount: 4
            )
            .opacity(0.15)
            .ignoresSafeArea()
        )
        #if os(iOS)
        .navigationTitle("Acknowledgment")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var sheetBody: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("GoodTerm")
                .font(.title)
                .fontWeight(.bold)

            Text("Made based on the open-source project Rayon")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Thanks to the creators of Rayon:")
                    .font(.headline)

                Text("[@Lakr233](https://twitter.com/Lakr233)")
                Text("[@__oquery](https://twitter.com/__oquery)")
                Text("[@zlind0](https://github.com/zlind0)")
                Text("[@unixzii](https://twitter.com/unixzii)")
                Text("[@82flex](https://twitter.com/82flex)")
                Text("[@xnth97](https://twitter.com/xnth97)")
            }
            .font(.body)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Source Code:")
                    .font(.headline)
                Link("[GitHub](https://github.com/Lakr233/Rayon)", destination: URL(string: "https://github.com/Lakr233/Rayon")!)
            }
        }
        .font(.system(.body, design: .rounded))
        .padding()
    }
}
