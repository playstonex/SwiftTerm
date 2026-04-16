//
//  SettingsCategoryList.swift
//  SettingsUI
//
//  Created for GoodTerm
//

import SwiftUI

// MARK: - Settings Category List (Sidebar — System Settings Style)
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
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(L10n.tr("Settings"))
    }
}
