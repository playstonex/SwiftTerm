//
//  SettingsItemList.swift
//  SettingsUI
//
//  Created for GoodTerm
//

import SwiftUI

// MARK: - Settings Item List (Second Column)
public struct SettingsItemList: View {
    let category: SettingsCategory
    @Binding var selectedItem: SettingsItem?

    public var body: some View {
        List(selection: $selectedItem) {
            ForEach(category.items) { item in
                ItemRow(item: item)
                    .tag(item)
            }
        }
        #if os(macOS)
        .listStyle(.plain)
        #else
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(category.rawValue)
    }
}

// MARK: - Item Row Component
public struct ItemRow: View {
    let item: SettingsItem

    public var body: some View {
        Text(item.rawValue)
            .font(.body)
            .lineLimit(1)
            .padding(.vertical, 2)
    }
}
