//
//  SettingsView.swift
//  SettingsUI
//
//  Created for GoodTerm
//

import DataSync
import Premium
import RayonModule
import SwiftUI

// MARK: - Main Settings View
public struct SettingsViewContainer: View {
    @EnvironmentObject var store: RayonStore
    @State private var selectedCategory: SettingsCategory?

    public init() {}

    public var body: some View {
        #if os(iOS)
        iOSSettingsNavigationView()
        #else
        NavigationSplitView {
            SettingsCategoryList(selectedCategory: $selectedCategory)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            CategoryContentView(category: selectedCategory ?? .about)
        }
        .onAppear {
            if selectedCategory == nil {
                selectedCategory = .about
            }
        }
        #endif
    }
}

#if os(iOS)
private struct iOSSettingsNavigationView: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(SettingsCategory.allCases) { category in
                    NavigationLink {
                        iOSMergedCategoryDetailView(category: category)
                    } label: {
                        CategoryRow(category: category)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Settings")
        }
    }
}

private struct iOSMergedCategoryDetailView: View {
    let category: SettingsCategory

    var body: some View {
        Form {
            ForEach(category.items) { item in
                SettingsDetailContent(item: item)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(category.rawValue)
    }
}
#endif

// MARK: - Category Content View (Merged Right Side)
public struct CategoryContentView: View {
    let category: SettingsCategory

    public var body: some View {
        Form {
            ForEach(category.items) { item in
                SettingsDetailContent(item: item)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(category.rawValue)
        .frame(maxWidth: 700)
        #if os(macOS)
        .scrollContentBackground(.hidden)
        #endif
    }
}

// MARK: - Category Row Component
public struct CategoryRow: View {
    let category: SettingsCategory

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(category.rawValue)
                .font(.body)
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

public struct SettingsView_Previews: PreviewProvider {
    public static var previews: some View {
        SettingsViewContainer()
            .environmentObject(RayonStore.shared)
    }
}
