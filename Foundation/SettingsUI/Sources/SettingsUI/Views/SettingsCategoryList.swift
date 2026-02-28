//
//  SettingsCategoryList.swift
//  SettingsUI
//
//  Created for GoodTerm
//

import SwiftUI

// MARK: - Settings Category List (First Column)
public struct SettingsCategoryList: View {
    @Binding var selectedCategory: SettingsCategory?

    public var body: some View {
        List(selection: $selectedCategory) {
            ForEach(SettingsCategory.allCases) { category in
                CategoryRow(category: category)
                    .tag(category)
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #else
        .listStyle(.plain)
        #endif
        .navigationTitle("Settings")
    }
}
